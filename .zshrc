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

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/opt/homebrew/share/google-cloud-sdk/path.zsh.inc' ]; then . '/opt/homebrew/share/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc' ]; then . '/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc'; fi

# Aliases for usual GitHub operations
alias gucb='git fetch && git pull'
alias gumb='CB=$(git rev-parse --abbrev-ref HEAD) && git checkout main && git fetch && git pull && git checkout $CB'
