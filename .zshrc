# Homebrew (Apple Silicon, Intel Mac, Linuxbrew)
for brew_prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  if [ -x "$brew_prefix/bin/brew" ]; then
    eval "$("$brew_prefix/bin/brew" shellenv)"
    break
  fi
done

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(git kubectl kubectx kube-ps1 zsh-interactive-cd zsh-navigation-tools zsh-fzf-history-search)

source $ZSH/oh-my-zsh.sh

# Kube info
PROMPT='$(kube_ps1) | %n@%m'$PROMPT

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

alias kctx="kubectx"
alias kns="kubens"

# Google Cloud SDK (Homebrew or ~/google-cloud-sdk)
if command -v brew >/dev/null 2>&1; then
  _gcloud_sdk="$(brew --prefix)/share/google-cloud-sdk"
  [ -f "$_gcloud_sdk/path.zsh.inc" ] && . "$_gcloud_sdk/path.zsh.inc"
  [ -f "$_gcloud_sdk/completion.zsh.inc" ] && . "$_gcloud_sdk/completion.zsh.inc"
  unset _gcloud_sdk
fi
if [ -f "$HOME/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$HOME/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/google-cloud-sdk/completion.zsh.inc"; fi

# Aliases for usual GitHub operations
alias gucb='git fetch && git pull'
alias gumb='CB=$(git rev-parse --abbrev-ref HEAD) && git checkout main && git fetch && git pull && git checkout $CB'
