# Path to your oh-my-zsh installation.
export ZSH=~/.oh-my-zsh

export PATH="$HOME/.local/bin:$PATH"
export AWS_PAGER=""
export DISABLE_MAGIC_FUNCTIONS=true

# resolve directory of this .zshrc (following symlinks) to locate repo files
SHELL_REPO_DIR="${${(%):-%x}:A:h}"

# only load oh-my-zsh (and its plugins) once it's been installed by update-shell
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-autocomplete fzf mise)
  source $ZSH/oh-my-zsh.sh
fi

if command -v oh-my-posh > /dev/null; then
  eval "$(oh-my-posh init zsh --config $SHELL_REPO_DIR/custom.omp.yml)"
fi

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

  echo "  ↳ installing zsh-autosuggestions"
  __update_or_clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

  echo "  ↳ installing zsh-syntax-highlighting"
  __update_or_clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

  echo "  ↳ installing zsh-autocomplete"
  __update_or_clone https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete main

  echo " => installing oh my posh (shell theme)"
  mkdir -p ~/.local/bin
  curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin > /dev/null

  echo "  ↳ installing meslo nerd font"
  ~/.local/bin/oh-my-posh font install --headless meslo

  echo " => installing fzf (fuzzy history search)"
  __update_or_clone https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --key-bindings --no-completion --no-update-rc > /dev/null

  echo " => installing 'mise' (version manager)"
  curl https://mise.run | sh > /dev/null
}

# autocomplete config
#bindkey '\t' menu-select "$terminfo[kcbt]" menu-select
#bindkey -M menuselect '\t' menu-complete "$terminfo[kcbt]" reverse-menu-complete

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

# disable file expansion: https://github.com/marlonrichert/zsh-autocomplete/issues/759#issuecomment-2439603287
zstyle ':completion:*' completer _complete _complete:-fuzzy _correct _approximate _ignored

# -- tools activation --
[[ -x ~/.fzf/bin/fzf ]] && source <(~/.fzf/bin/fzf --zsh)
[[ -x ~/.local/bin/mise ]] && eval "$(~/.local/bin/mise activate zsh)"
