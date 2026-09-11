#!/usr/bin/env bash
# Bootstrap a plain machine (VM or bare metal) to match this shell setup.
# Usage:
#   ./install.sh                 # core install; prompts for optional tools
#   ./install.sh --all           # install everything, no prompts
#   ./install.sh --update        # refresh ~/.zshrc and custom plugins
#   ./install.sh --uninstall     # restore previous ~/.zshrc; remove our plugins
#   curl -fsSL <raw-url> | bash
#   curl -fsSL <raw-url> | bash -s -- --all|--update|--uninstall [--yes]
set -euo pipefail

REPO_RAW_BASE="${OHMYZSH_CONFIG_RAW_BASE:-https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main}"

# When run via `curl | bash`, BASH_SOURCE points at a fifo/fd without a repo checkout.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  _candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$_candidate/.zshrc" ]]; then
    SCRIPT_DIR="$_candidate"
  fi
fi
unset _candidate

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
INSTALL_ALL=0
WITH_KUBECTL=0
WITH_GCLOUD=0
WITH_CURSOR=0
UPDATE=0
UNINSTALL=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --all) INSTALL_ALL=1 ;;
    --update) UPDATE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--all] [--update] [--uninstall] [--yes]

  (default)     Install core tooling, then ask interactively about
                kubectl/kubectx, Google Cloud SDK, and Cursor CLI.
  --all         Install everything without prompting.
  --update      On an existing machine, refresh ~/.zshrc from this repo
                and update custom Oh My Zsh plugins. Does not reinstall
                Homebrew, nvm, or optional CLIs.
  --uninstall   Restore the original ~/.zshrc (oldest backup) and remove
                plugins this script added. Leaves Homebrew, nvm, Oh My Zsh,
                and brew packages in place unless you confirm extra removals.
  --yes         Skip confirmation prompts (for --uninstall).

Also supports:
  curl -fsSL $REPO_RAW_BASE/install.sh | bash
  curl -fsSL $REPO_RAW_BASE/install.sh | bash -s -- --all
  curl -fsSL $REPO_RAW_BASE/install.sh | bash -s -- --update
  curl -fsSL $REPO_RAW_BASE/install.sh | bash -s -- --uninstall --yes
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$UPDATE" -eq 1 && "$UNINSTALL" -eq 1 ]]; then
  echo "Use either --update or --uninstall, not both" >&2
  exit 1
fi

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

# Prefer /dev/tty so prompts still work when the script itself is piped on stdin.
can_prompt() {
  if [[ -t 0 ]]; then
    return 0
  fi
  # /dev/tty may exist as a device node but be unusable (e.g. no controlling TTY).
  if { true >/dev/tty; } 2>/dev/null; then
    return 0
  fi
  return 1
}

read_reply() {
  local __var="$1"
  if [[ -t 0 ]]; then
    read -r "$__var"
  else
    read -r "$__var" </dev/tty
  fi
}

ask_yes_no() {
  local prompt="$1"
  local reply

  if ! can_prompt; then
    warn "Non-interactive session; answering no to: $prompt"
    return 1
  fi

  while true; do
    printf '\033[1;34m==>\033[0m %s [y/N] ' "$prompt"
    read_reply reply || return 1
    case "${reply:-}" in
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]|"") return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

resolve_optional_installs() {
  if [[ "$INSTALL_ALL" -eq 1 ]]; then
    WITH_KUBECTL=1
    WITH_GCLOUD=1
    WITH_CURSOR=1
    ok "Installing everything (--all)"
    return
  fi

  if ask_yes_no "Install kubectl and kubectx?"; then
    WITH_KUBECTL=1
  else
    ok "Skipping kubectl and kubectx"
  fi

  if ask_yes_no "Install Google Cloud SDK?"; then
    WITH_GCLOUD=1
  else
    ok "Skipping Google Cloud SDK"
  fi

  if ask_yes_no "Install Cursor CLI?"; then
    WITH_CURSOR=1
  else
    ok "Skipping Cursor CLI"
  fi
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)  echo linux ;;
    *)      echo unsupported ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return
  fi
  if ! have sudo; then
    fail "sudo is required for package installs"
  fi
  # Prefer non-interactive check (works over SSH without a TTY / with NOPASSWD).
  if sudo -n true 2>/dev/null; then
    return
  fi
  # When the script is piped on stdin, prompt via /dev/tty if available.
  if [[ -t 0 ]]; then
    sudo -v || fail "sudo authentication failed"
    return
  fi
  if { true >/dev/tty; } 2>/dev/null; then
    sudo -v </dev/tty || fail "sudo authentication failed"
    return
  fi
  fail "sudo needs a password, but this session is non-interactive. Re-run with a TTY (ssh -t) or configure NOPASSWD."
}

# Keep sudo alive while the script runs (only needed when a timestamped credential is used).
keep_sudo_alive() {
  if [[ "$(id -u)" -eq 0 ]] || ! have sudo; then
    return
  fi
  if sudo -n true 2>/dev/null; then
    return
  fi
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &
}

install_system_packages() {
  info "Installing system packages..."
  case "$(detect_os)" in
    macos)
      if ! xcode-select -p >/dev/null 2>&1; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install || true
        warn "If CLT install opened a dialog, finish it and re-run this script"
      fi
      ;;
    linux)
      ensure_sudo
      if have apt-get; then
        sudo apt-get update -y
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
          build-essential curl file git ca-certificates procps unzip \
          zsh
      elif have dnf; then
        sudo dnf install -y \
          @development-tools curl file git ca-certificates procps-ng unzip \
          zsh
      elif have pacman; then
        sudo pacman -Sy --noconfirm \
          base-devel curl file git ca-certificates procps-ng unzip \
          zsh
      else
        fail "Unsupported Linux package manager (need apt, dnf, or pacman)"
      fi
      ;;
    *)
      fail "Unsupported OS: $(uname -s)"
      ;;
  esac
  ok "System packages ready"
}

install_zsh() {
  if have zsh; then
    ok "zsh already installed: $(command -v zsh)"
    return
  fi

  info "Installing zsh..."
  case "$(detect_os)" in
    macos)
      if have brew; then
        brew install zsh
      else
        fail "zsh missing and Homebrew not available yet"
      fi
      ;;
    linux)
      # Usually installed by install_system_packages
      have zsh || fail "zsh install failed"
      ;;
  esac
  ok "zsh installed"
}

brew_shellenv() {
  for prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    if [[ -x "$prefix/bin/brew" ]]; then
      eval "$("$prefix/bin/brew" shellenv)"
      return 0
    fi
  done
  return 1
}

install_homebrew() {
  if brew_shellenv; then
    ok "Homebrew already installed: $(command -v brew)"
    return
  fi

  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  brew_shellenv || fail "Homebrew installed but not found on PATH"
  ok "Homebrew installed"
}

brew_install() {
  local pkg="$1"
  if brew list --formula "$pkg" >/dev/null 2>&1 || brew list --cask "$pkg" >/dev/null 2>&1; then
    ok "brew: $pkg already installed"
    return
  fi
  info "brew install $pkg"
  brew install "$pkg"
}

install_gcloud() {
  if [[ "$WITH_GCLOUD" -ne 1 ]]; then
    return
  fi

  if have gcloud; then
    ok "gcloud already installed"
    return
  fi

  info "Installing Google Cloud SDK..."
  case "$(detect_os)" in
    macos)
      if brew install --cask google-cloud-sdk; then
        ok "google-cloud-sdk installed via Homebrew cask"
        return
      fi
      ;;
    linux)
      if brew install google-cloud-sdk 2>/dev/null; then
        ok "google-cloud-sdk installed via Homebrew"
        return
      fi
      ;;
  esac

  # Fallback: official installer into ~/google-cloud-sdk (no shell rc edits)
  curl -fsSL https://sdk.cloud.google.com | bash -s -- \
    --disable-prompts \
    --install-dir="$HOME" \
    --quiet
  ok "google-cloud-sdk installed to $HOME/google-cloud-sdk"
}

install_kubectl() {
  if [[ "$WITH_KUBECTL" -ne 1 ]]; then
    return
  fi

  brew_install kubectl
  brew_install kubectx
}

install_cli_tools() {
  brew_shellenv || fail "Homebrew is required"

  info "Installing CLI tools via Homebrew..."
  brew_install fzf
  brew_install git
  install_kubectl
  install_gcloud

  # Key bindings / completion for fzf
  if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
    info "Configuring fzf key bindings..."
    "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish >/dev/null
  fi

  ok "CLI tools ready"
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "Oh My Zsh already installed"
    return
  fi

  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "Oh My Zsh installed"
}

clone_plugin() {
  local name="$1"
  local repo="$2"
  local dest="$ZSH_CUSTOM_DIR/plugins/$name"

  mkdir -p "$ZSH_CUSTOM_DIR/plugins"
  if [[ -d "$dest/.git" ]]; then
    if [[ "$UPDATE" -eq 1 ]]; then
      info "Updating plugin: $name"
      if git -C "$dest" pull --ff-only >/dev/null 2>&1; then
        ok "Plugin $name updated"
      else
        warn "Could not update plugin $name"
      fi
    else
      ok "Plugin $name already present"
    fi
    return
  fi

  info "Installing plugin: $name"
  rm -rf "$dest"
  git clone --depth=1 "$repo" "$dest"
}

install_custom_plugins() {
  info "Installing custom Oh My Zsh plugins..."
  clone_plugin zsh-interactive-cd "https://github.com/changyuheng/zsh-interactive-cd.git"
  clone_plugin zsh-fzf-history-search "https://github.com/joshskidmore/zsh-fzf-history-search.git"
  if [[ "$WITH_KUBECTL" -eq 1 ]] || have kubectl; then
    clone_plugin kube-ps1 "https://github.com/jonmosco/kube-ps1.git"
    clone_plugin kubectx "https://github.com/unixorn/kubectx-zshplugin.git"
  fi
  ok "Custom plugins ready"
}

install_nvm() {
  export NVM_DIR="$HOME/.nvm"

  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    ok "nvm already installed"
    return
  fi

  info "Installing nvm..."
  # Do not modify shell rc files; our .zshrc already loads nvm.
  PROFILE=/dev/null bash -c \
    'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
  ok "nvm installed"
}

install_zshrc() {
  local source_rc=""
  local target_rc="$HOME/.zshrc"
  local tmp=""

  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/.zshrc" ]]; then
    source_rc="$SCRIPT_DIR/.zshrc"
  else
    info "Fetching .zshrc from $REPO_RAW_BASE/.zshrc"
    have curl || fail "curl is required to download .zshrc when not running from a repo checkout"
    tmp="$(mktemp)"
    curl -fsSL "$REPO_RAW_BASE/.zshrc" -o "$tmp" || {
      rm -f "$tmp"
      fail "Failed to download .zshrc"
    }
    source_rc="$tmp"
  fi

  if [[ -f "$target_rc" || -L "$target_rc" ]]; then
    if cmp -s "$source_rc" "$target_rc"; then
      ok "~/.zshrc already up to date"
      [[ -n "$tmp" ]] && rm -f "$tmp"
      return
    fi
    local backup="$target_rc.backup.$(date +%Y%m%d%H%M%S)"
    info "Backing up existing ~/.zshrc to $backup"
    mv "$target_rc" "$backup"
  fi

  info "Installing repo .zshrc as ~/.zshrc"
  cp "$source_rc" "$target_rc"
  [[ -n "$tmp" ]] && rm -f "$tmp"
  ok "~/.zshrc installed"
}

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    ok "Default shell already set to zsh"
    return
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    warn "Running as root; skip chsh for a normal user account"
    return
  fi

  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    info "Adding $zsh_path to /etc/shells"
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  info "Setting zsh as default shell..."
  if chsh -s "$zsh_path" 2>/dev/null; then
    ok "Default shell set to $zsh_path"
    return
  fi

  # chsh often needs a password interactively; fall back to sudo when available.
  if have sudo && sudo -n true 2>/dev/null; then
    if sudo chsh -s "$zsh_path" "$USER"; then
      ok "Default shell set to $zsh_path (via sudo)"
      return
    fi
  fi

  warn "chsh failed; run manually: chsh -s $zsh_path"
}

install_cursor_cli() {
  if [[ "$WITH_CURSOR" -ne 1 ]]; then
    return
  fi

  info "Installing Cursor CLI..."
  curl -fsS https://cursor.com/install | bash
  ok "Cursor CLI installed"
}

update_existing() {
  info "Updating ohmyzsh-config on this machine"
  brew_shellenv || true
  have git || fail "git is required to update plugins"
  have curl || fail "curl is required to fetch .zshrc when not running from a checkout"

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    fail "Oh My Zsh is not installed. Run without --update to bootstrap this machine."
  fi
  install_custom_plugins
  install_zshrc

  cat <<EOF

------------------------------------------------------------
Update complete.
  - ~/.zshrc refreshed from this repository
  - custom Oh My Zsh plugins pulled / installed if missing

Start a new login shell to pick up prompt changes:
  exec zsh -l
------------------------------------------------------------
EOF
}

oldest_zshrc_backup() {
  local backups=()
  local f
  for f in "$HOME"/.zshrc.backup.*; do
    [[ -e "$f" ]] || continue
    backups+=("$f")
  done
  if [[ "${#backups[@]}" -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${backups[@]}" | sort | head -n 1
}

remove_plugin() {
  local name="$1"
  local dest="$ZSH_CUSTOM_DIR/plugins/$name"
  if [[ -d "$dest" ]]; then
    info "Removing plugin: $name"
    rm -rf "$dest"
    ok "Removed $dest"
  fi
}

uninstall_config() {
  if [[ "$ASSUME_YES" -ne 1 ]]; then
    if ! can_prompt; then
      fail "Uninstall needs confirmation. Re-run with --uninstall --yes"
    fi
    if ! ask_yes_no "Remove this shell config (restore ~/.zshrc, delete our Oh My Zsh plugins)?"; then
      warn "Uninstall cancelled"
      exit 0
    fi
  fi

  info "Uninstalling ohmyzsh-config"

  local backup=""
  if backup="$(oldest_zshrc_backup)"; then
    if [[ -f "$HOME/.zshrc" || -L "$HOME/.zshrc" ]]; then
      local removed="$HOME/.zshrc.removed.$(date +%Y%m%d%H%M%S)"
      info "Saving current ~/.zshrc to $removed"
      mv "$HOME/.zshrc" "$removed"
    fi
    info "Restoring ~/.zshrc from oldest backup: $backup"
    cp "$backup" "$HOME/.zshrc"
    ok "~/.zshrc restored"
  else
    warn "No ~/.zshrc.backup.* found; leaving current ~/.zshrc in place"
  fi

  remove_plugin zsh-interactive-cd
  remove_plugin zsh-fzf-history-search
  remove_plugin kube-ps1
  remove_plugin kubectx

  local remove_omz=0
  local remove_nvm=0
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    ok "Leaving Oh My Zsh, nvm, Homebrew, and brew packages installed"
  else
    if [[ -d "$HOME/.oh-my-zsh" ]] && ask_yes_no "Also remove Oh My Zsh (~/.oh-my-zsh)?"; then
      remove_omz=1
    fi
    if [[ -d "$HOME/.nvm" ]] && ask_yes_no "Also remove nvm (~/.nvm)?"; then
      remove_nvm=1
    fi
  fi

  if [[ "$remove_omz" -eq 1 ]]; then
    rm -rf "$HOME/.oh-my-zsh"
    ok "Removed ~/.oh-my-zsh"
  fi
  if [[ "$remove_nvm" -eq 1 ]]; then
    rm -rf "$HOME/.nvm"
    ok "Removed ~/.nvm"
  fi

  cat <<EOF

------------------------------------------------------------
Uninstall complete.
  - ~/.zshrc restored from backup (if one existed)
  - custom plugins from this repo removed

Left in place (not owned only by this script):
  - Homebrew and brew packages (zsh, git, fzf, kubectl, ...)
  - Google Cloud SDK / Cursor CLI if they were installed
  - Oh My Zsh and nvm, unless you confirmed removal

Open a new shell:
  exec zsh -l
------------------------------------------------------------
EOF
}

print_summary() {
  local kubectl_line="  - kubectl / kubectx: skipped"
  local gcloud_line="  - Google Cloud SDK: skipped"
  local cursor_line="  - Cursor CLI: skipped"

  [[ "$WITH_KUBECTL" -eq 1 ]] && kubectl_line="  - kubectl / kubectx: installed"
  [[ "$WITH_GCLOUD" -eq 1 ]] && gcloud_line="  - Google Cloud SDK: installed"
  [[ "$WITH_CURSOR" -eq 1 ]] && cursor_line="  - Cursor CLI: installed"

  cat <<EOF

------------------------------------------------------------
Setup complete. This machine now has:
  - zsh + Oh My Zsh (robbyrussell)
  - Homebrew + fzf, git
  - nvm
  - custom plugins from this repo's .zshrc
  - ~/.zshrc from this repository
$kubectl_line
$gcloud_line
$cursor_line

Next steps:
  1. Start a new login shell:  exec zsh -l
  2. (Optional) install a Node version:  nvm install --lts
------------------------------------------------------------
EOF
}

main() {
  if [[ "$UNINSTALL" -eq 1 ]]; then
    uninstall_config
    return
  fi

  if [[ "$UPDATE" -eq 1 ]]; then
    update_existing
    return
  fi

  info "Bootstrapping shell environment from ohmyzsh-config"
  resolve_optional_installs
  ensure_sudo
  keep_sudo_alive
  install_system_packages
  install_zsh
  install_homebrew
  install_cli_tools
  install_oh_my_zsh
  install_custom_plugins
  install_nvm
  install_zshrc
  set_default_shell
  install_cursor_cli
  print_summary
}

main "$@"
