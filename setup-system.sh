#!/usr/bin/env bash
#
# Sets up a fresh Ubuntu/GNOME system the way I like it:
#   - Dracula GTK theme + Dracula GNOME Shell theme (enabled via User Themes)
#   - my GNOME extensions (Dash to Dock, Frippery Move Clock, User Themes)
#   - Dash to Dock instead of the Ubuntu Dock
#   - gnome-terminal colors/font matching the shell prompt
#   - pass + browserpass (Chrome extension + native host)
#   - git config with separate personal / roche identities
#
# Everything else in Chrome syncs through the Google account.
#
# Usage:
#   ./setup-system.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRACULA_GTK_REPO="https://github.com/dracula/gtk.git"
THEME_NAME="Dracula"
THEME_DIR="$HOME/.themes/$THEME_NAME"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"

PASSWORD_STORE_REPO="git@github.com:randombenj/secrets.git"
PASSWORD_STORE_DIR="$HOME/.password-store"
PASS_GPG_ID="randombenj@gmail.com"
BROWSERPASS_VERSION="3.1.2"

ENABLED_EXTENSIONS=(
  "user-theme@gnome-shell-extensions.gcampax.github.com"
  "dash-to-dock@micxgx.gmail.com"
  "Move_Clock@rmy.pobox.com"
  "ubuntu-appindicators@ubuntu.com" # ships with Ubuntu, not installed from EGO
)

# installed from extensions.gnome.org
EGO_EXTENSIONS=(
  "user-theme@gnome-shell-extensions.gcampax.github.com"
  "dash-to-dock@micxgx.gmail.com"
  "Move_Clock@rmy.pobox.com"
)

DISABLED_EXTENSIONS=(
  "ubuntu-dock@ubuntu.com" # replaced by dash-to-dock
  "tiling-assistant@ubuntu.com"
  "ding@rastersoft.com"
)

log() { echo " => $*"; }
sub() { echo "  ↳ $*"; }

require_gnome() {
  command -v gnome-shell >/dev/null || {
    echo "[ERROR] gnome-shell not found, this script targets GNOME" >&2
    exit 1
  }
}

install_packages() {
  log "installing dependencies"
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    git git-lfs curl unzip jq dconf-cli gnome-shell-extension-manager \
    pass gnupg pinentry-gnome3 make
}

link_config() {
  # symlink a dotfile from this repo into $HOME, backing up whatever was there
  local src="$REPO_DIR/$1" dst="$HOME/$1"

  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$src" ]; then
    sub "$1 already linked"
    return 0
  fi
  if [ -e "$dst" ]; then
    sub "backing up existing $1 to $1.bak"
    mv "$dst" "$dst.bak"
  fi
  sub "linking $1"
  ln -sfn "$src" "$dst"
}

configure_git() {
  log "configuring git"
  # ~/.gitconfig includes the per-directory identity:
  #   ~/Work/personal/* -> randombenj@gmail.com  + ~/.ssh/id_ed25519
  #   ~/Work/roche/*    -> work address          + ~/.ssh/id_ed25519_roche
  link_config .gitconfig
  link_config .gitconfig-personal

  # copied rather than linked: the work address stays out of this public repo
  if [ -e "$HOME/.gitconfig-roche" ]; then
    sub ".gitconfig-roche already present"
  else
    sub "creating .gitconfig-roche"
    cp "$REPO_DIR/.gitconfig-roche" "$HOME/.gitconfig-roche"
    echo "     [TODO] set the real address in ~/.gitconfig-roche" >&2
  fi

  local key
  for key in id_ed25519 id_ed25519_roche; do
    [ -f "$HOME/.ssh/$key" ] || echo "     [WARN] ~/.ssh/$key is missing, restore it from a backup" >&2
  done
}

install_pass() {
  log "setting up pass"

  if ! gpg --list-secret-keys "$PASS_GPG_ID" >/dev/null 2>&1; then
    echo "     [WARN] no secret GPG key for $PASS_GPG_ID" >&2
    echo "            restore it first:  gpg --import <backup.asc> && gpg --edit-key $PASS_GPG_ID trust" >&2
    return 0
  fi

  if [ -d "$PASSWORD_STORE_DIR/.git" ]; then
    sub "password store already cloned, pulling"
    git -C "$PASSWORD_STORE_DIR" pull --quiet --ff-only || echo "     [WARN] could not update the password store" >&2
  elif [ -e "$PASSWORD_STORE_DIR" ]; then
    sub "$PASSWORD_STORE_DIR exists but is not a git clone, leaving it alone"
  else
    sub "cloning the password store"
    git clone --quiet "$PASSWORD_STORE_REPO" "$PASSWORD_STORE_DIR" \
      || echo "     [WARN] clone failed, is ~/.ssh/id_ed25519 present and added to GitHub?" >&2
  fi
}

install_browserpass() {
  log "installing the browserpass native host"

  if [ -x /usr/bin/browserpass-linux64 ]; then
    sub "already installed, skipping"
  else
    local tmp src
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    sub "downloading browserpass-native $BROWSERPASS_VERSION"
    curl -fsSL -o "$tmp/browserpass.tar.gz" \
      "https://github.com/browserpass/browserpass-native/releases/download/${BROWSERPASS_VERSION}/browserpass-linux64-${BROWSERPASS_VERSION}.tar.gz"
    tar -xzf "$tmp/browserpass.tar.gz" -C "$tmp"

    src="$tmp/browserpass-linux64-${BROWSERPASS_VERSION}"
    make -C "$src" BIN=browserpass-linux64 configure >/dev/null
    sudo make -C "$src" BIN=browserpass-linux64 install >/dev/null
  fi

  # `install` drops the Makefile in /usr/lib/browserpass, the *-user target
  # symlinks the host manifest into the Chrome profile directory
  sub "registering the native host with Chrome"
  make -C /usr/lib/browserpass hosts-chrome-user >/dev/null

  # the only Chrome extension that does not come in through account sync,
  # installed via managed policy so a fresh profile picks it up automatically
  sub "installing the Browserpass Chrome extension"
  sudo make -C /usr/lib/browserpass policies-chrome >/dev/null
}

install_gtk_theme() {
  log "installing the Dracula GTK theme"
  mkdir -p "$HOME/.themes"
  if [ -d "$THEME_DIR/.git" ]; then
    sub "already present, updating"
    git -C "$THEME_DIR" pull --quiet --ff-only
  else
    rm -rf "$THEME_DIR"
    git clone --quiet --depth 1 "$DRACULA_GTK_REPO" "$THEME_DIR"
  fi
}

install_gnome_extension() {
  # Download and install an extension from extensions.gnome.org for the running shell.
  local uuid="$1"
  local shell_version info url tmp

  if [ -d "$EXT_DIR/$uuid" ]; then
    sub "$uuid already installed, skipping"
    return 0
  fi

  shell_version="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
  info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_version}")" || {
    echo "     [WARN] $uuid is not available for GNOME $shell_version" >&2
    return 0
  }

  url="https://extensions.gnome.org$(jq -r '.download_url' <<<"$info")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  sub "installing $uuid"
  curl -fsSL -o "$tmp/ext.zip" "$url"
  # gnome-extensions takes care of unpacking and compiling the gsettings schemas
  gnome-extensions install --force "$tmp/ext.zip"
}

install_gnome_extensions() {
  log "installing GNOME extensions"
  for uuid in "${EGO_EXTENSIONS[@]}"; do
    install_gnome_extension "$uuid"
  done
}

toggle_gnome_extensions() {
  log "enabling / disabling GNOME extensions"
  for uuid in "${DISABLED_EXTENSIONS[@]}"; do
    gnome-extensions disable "$uuid" 2>/dev/null || true
  done
  for uuid in "${ENABLED_EXTENSIONS[@]}"; do
    # newly installed extensions only become enableable after a shell restart,
    # so write the list directly instead of relying on `gnome-extensions enable`
    gnome-extensions enable "$uuid" 2>/dev/null || true
  done

  local list
  list="$(printf "'%s', " "${ENABLED_EXTENSIONS[@]}")"
  gsettings set org.gnome.shell enabled-extensions "[${list%, }]"

  list="$(printf "'%s', " "${DISABLED_EXTENSIONS[@]}")"
  gsettings set org.gnome.shell disabled-extensions "[${list%, }]"
}

apply_theme() {
  log "applying the Dracula theme"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme "$THEME_NAME"
  gsettings set org.gnome.desktop.wm.preferences theme "$THEME_NAME"
  gsettings set org.gnome.desktop.interface icon-theme 'Yaru'
  gsettings set org.gnome.desktop.interface cursor-theme 'Yaru'
  gsettings set org.gnome.desktop.interface font-name 'Ubuntu Sans 11'

  sub "enabling the GNOME Shell theme"
  # the schema lives with the extension, so point gsettings at it in case the
  # extension has not been loaded by the running shell yet
  local schemadir="$EXT_DIR/user-theme@gnome-shell-extensions.gcampax.github.com/schemas"
  if [ -d "$schemadir" ]; then
    gsettings --schemadir "$schemadir" set org.gnome.shell.extensions.user-theme name "$THEME_NAME"
  else
    gsettings set org.gnome.shell.extensions.user-theme name "$THEME_NAME"
  fi
}

configure_dash_to_dock() {
  log "configuring Dash to Dock"
  local d=/org/gnome/shell/extensions/dash-to-dock
  dconf write $d/dock-position "'BOTTOM'"
  dconf write $d/dock-fixed false
  dconf write $d/extend-height false
  dconf write $d/height-fraction 0.9
  dconf write $d/dash-max-icon-size 64
  dconf write $d/icon-size-fixed false
  dconf write $d/background-opacity 0.8
  dconf write $d/click-action "'cycle-windows'"
  dconf write $d/preferred-monitor -2
  dconf write $d/preferred-monitor-by-connector "'primary'"
  dconf write $d/show-trash false
  dconf write $d/show-mounts-network false
  dconf write $d/show-mounts-only-mounted true

  gsettings set org.gnome.shell favorite-apps \
    "['google-chrome.desktop', 'org.gnome.Terminal.desktop', 'code.desktop']"
}

configure_terminal() {
  log "configuring gnome-terminal"
  local profile p
  profile="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')"
  p="/org/gnome/terminal/legacy/profiles:/:$profile"

  dconf write "$p/use-theme-colors" false
  dconf write "$p/background-color" "'rgb(30,31,41)'"
  dconf write "$p/foreground-color" "'rgb(208,207,204)'"
  dconf write "$p/use-theme-transparency" true
  dconf write "$p/use-system-font" false
  dconf write "$p/font" "'MesloLGS Nerd Font Mono 12'"
  dconf write "$p/scrollback-unlimited" true
  dconf write "$p/bold-is-bright" false
  # zsh as the terminal shell without changing the login shell
  dconf write "$p/use-custom-command" true
  dconf write "$p/custom-command" "'zsh'"
}

main() {
  require_gnome
  install_packages
  configure_git
  install_gtk_theme
  install_gnome_extensions
  toggle_gnome_extensions
  apply_theme
  configure_dash_to_dock
  configure_terminal
  install_pass
  install_browserpass

  echo
  echo " => done, log out and back in for the shell theme and extensions to load"
}

main "$@"
