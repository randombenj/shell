# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

plugins=(git asdf zsh-syntax-highlighting zsh-autosuggestions zsh-autocomplete)

# User configuration
if [ -f $ZSH_CUSTOM/path.sh ]; then
    source $ZSH_CUSTOM/path.sh
fi

export PATH="$HOME/.local/bin:$PATH"
source $ZSH/oh-my-zsh.sh
eval "$(oh-my-posh init zsh --config https://gist.githubusercontent.com/randombenj/30a33a8ba24154562b90747c8df20d2f/raw/custom.omp.yml)"

alias ip="ip --color"

c() {
  # Ask cheat.sh website for details about a Linux command.
  curl -m 10 "http://cheat.sh/${1}" 2>/dev/null || printf '%s\n' "[ERROR] Something broke"
}

update-shell() {

  echo " => installing oh my zsh"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --keep-zshrc > /dev/null

  __update_or_clone() {
    # Clone or pull (update) a oh-my-zsh plugin
    # __update_or_clone git://git@... ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/... [BRANCH] [REMOTE]

    local repo="$1"
    local dir="$2"
    local branch="${3:-master}"
    local remote="${4:-origin}"

    if [ -d "$dir" ]
    then
      git -C $dir pull --quiet $remote $branch
    else
      git clone --quiet $repo $dir
    fi
  }

  __checkout_latest() {
    local dir="$1"

    git -C $dir fetch --tags
    local latest=$(git -C $dir describe --tags "$(git -C $dir rev-list --tags --max-count=1)")
    git -C $dir checkout --quiet $latest
  }

  echo "  ↳ installing zsh-autosuggestions"
  __update_or_clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

  echo "  ↳ installing zsh-syntax-highligting"
  __update_or_clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

  echo "  ↳ installing zsh-autocomplete"
  __update_or_clone https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete main

  echo " => installing oh my posh (shell theme)"
  mkdir -p ~/.local/bin
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin > /dev/null

  echo " => installing fzf (fuzzy history search)"
  __update_or_clone https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --key-bindings --no-completion --no-update-rc > /dev/null

  echo " => installing 'asdf' (version manager)"
  __update_or_clone https://github.com/asdf-vm/asdf.git ~/.asdf
  __checkout_latest ~/.asdf
}

# autocomplete config
bindkey '\t' menu-select "$terminfo[kcbt]" menu-select
bindkey -M menuselect '\t' menu-complete "$terminfo[kcbt]" reverse-menu-complete

# reset autocomplete history to default
() {
   local -a prefix=( '\e'{\[,O} )
   local -a up=( ${^prefix}A ) down=( ${^prefix}B )
   local key=
   for key in $up[@]; do
      bindkey "$key" up-line-or-history
   done
   for key in $down[@]; do
      bindkey "$key" down-line-or-history
   done
}

BASE16_SHELL="$HOME/.config/base16-shell/base16-solarized.dark.sh"
[[ -s $BASE16_SHELL ]] && source $BASE16_SHELL

source <(fzf --zsh)
