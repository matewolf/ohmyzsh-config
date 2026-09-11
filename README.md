# ohmyzsh-config

Bootstrap a plain VM (or fresh machine) with the same zsh setup used on a daily driver.

## Install

One-liner (no clone):

```bash
curl -fsSL https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main/install.sh | bash
```

Install everything without prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main/install.sh | bash -s -- --all
```

Or clone first:

```bash
git clone https://github.com/matewolf/ohmyzsh-config.git ~/.ohmyzsh-config && ~/.ohmyzsh-config/install.sh
```

You will be asked interactively whether to install kubectl/kubectx, Google Cloud SDK, and Cursor CLI (when a TTY is available).

Then open a new shell:

```bash
exec zsh -l
```

## Update an existing machine

Refresh `~/.zshrc` and custom plugins without reinstalling Homebrew, nvm, or optional CLIs:

```bash
curl -fsSL https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main/install.sh | bash -s -- --update
```

Or from a clone:

```bash
~/.ohmyzsh-config/install.sh --update
```

Then `exec zsh -l`.

## Uninstall

Restore the original `~/.zshrc` (oldest `~/.zshrc.backup.*`) and remove plugins this script added. Homebrew, brew packages, Oh My Zsh, and nvm stay unless you confirm extra removals:

```bash
curl -fsSL https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main/install.sh | bash -s -- --uninstall
```

Non-interactive:

```bash
curl -fsSL https://raw.githubusercontent.com/matewolf/ohmyzsh-config/refs/heads/main/install.sh | bash -s -- --uninstall --yes
```

## What it installs

Always:
- zsh (default shell) + Oh My Zsh
- Homebrew
- fzf, git
- nvm
- custom plugins required by `.zshrc`
- this repo’s `.zshrc` as `~.zshrc` (existing file is backed up)

Optional (prompted, or included with `--all`):
- kubectl and kubectx
- Google Cloud SDK
- Cursor CLI
