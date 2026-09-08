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

  # WORKAROUND: oh-my-zsh runs compinit before zsh-autocomplete prepends its
  # Completions dir to fpath, so the plugin's #autoload helpers never get
  # registered and it errors with `command not found: _autocomplete__*`.
  () {
    setopt localoptions extendedglob
    local -a helpers=(
      ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete/Completions/_*~*.zwc(N-.:t)
    )
    (( $#helpers )) && autoload -Uz $helpers
  }
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

  # Run a command silently, replaying its output only if it fails.
  __quiet() {
    local out
    out="$("$@" 2>&1)" && return 0
    print -u2 -- "$out"
    return 1
  }

  echo " => installing oh my zsh"
  # install.sh refuses to run when $ZSH already exists; updates go through upgrade.sh instead.
  if [ -d "$ZSH" ]; then
    __quiet zsh "$ZSH/tools/upgrade.sh" || echo "     [WARN] could not update oh-my-zsh"
  else
    __quiet sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --keep-zshrc \
      || echo "     [WARN] could not install oh-my-zsh"
  fi

  __update_or_clone() {
    # Clone or pull (update) a oh-my-zsh plugin
    # __update_or_clone git://git@... ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/... [BRANCH] [REMOTE]

    local repo="$1"
    local dir="$2"
    local branch="${3:-master}"
    local remote="${4:-origin}"

    if [ -d "$dir" ]
    then
      __quiet git -C $dir pull --quiet $remote $branch
    else
      __quiet git clone --quiet $repo $dir
    fi || echo "     [WARN] could not update ${dir:t}"
  }

  echo "  ↳ installing zsh-autosuggestions"
  __update_or_clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

  echo "  ↳ installing zsh-syntax-highlighting"
  __update_or_clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

  echo "  ↳ installing zsh-autocomplete"
  __update_or_clone https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete main

  echo " => installing oh my posh (shell theme)"
  mkdir -p ~/.local/bin
  __quiet sh -c 'curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin'

  echo "  ↳ installing meslo nerd font"
  if fc-list 2>/dev/null | grep -qi 'Meslo.*Nerd Font'; then
    echo "     already present, skipping"
  # Installing by name resolves via the GitHub API, which is rate-limited per egress IP.
  elif ! __quiet ~/.local/bin/oh-my-posh font install --plain \
      https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip; then
    echo "     [WARN] meslo install failed, skipping"
  fi

  echo " => installing fzf (fuzzy history search)"
  __update_or_clone https://github.com/junegunn/fzf.git ~/.fzf
  __quiet ~/.fzf/install --key-bindings --no-completion --no-update-rc

  echo " => installing 'mise' (version manager)"
  __quiet sh -c 'curl -fsSL https://mise.run | sh'
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
