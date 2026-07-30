# ohmyzsh-config

Bootstrap a plain VM (or fresh machine) with the same zsh setup used on a daily driver.

## Install

```bash
git clone https://github.com/matewolf/ohmyzsh-config.git ~/.ohmyzsh-config && ~/.ohmyzsh-config/install.sh
```

Optional Cursor CLI:

```bash
./install.sh --with-cursor
```

Then open a new shell:

```bash
exec zsh -l
```

## What it installs

- zsh (default shell) + Oh My Zsh
- Homebrew
- fzf, kubectl, kubectx, git, Google Cloud SDK
- nvm
- custom plugins required by `.zshrc`
- this repo’s `.zshrc` as `~/.zshrc` (existing file is backed up)
