#!/usr/bin/env bash
#
# Sets up a fresh Ubuntu/GNOME system the way I like it:
#   - Dracula GTK theme + Dracula GNOME Shell theme (enabled via User Themes)
#   - my GNOME extensions (Dash to Dock, Frippery Move Clock, User Themes)
#   - Dash to Dock instead of the Ubuntu Dock
#   - zsh + .zshrc, the Meslo Nerd Font and gnome-terminal colors/font
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

# the gnome-terminal profile below is set to this family, so it has to exist
NERD_FONT_ZIP="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
FONT_DIR="$HOME/.local/share/fonts/MesloLGS-NF"

# appimaged watches this directory (and ~/Downloads) and writes the .desktop files
APPIMAGE_DIR="$HOME/Applications"

# 1 = light: what prefers-color-scheme reports to websites, the Chrome UI itself
# keeps following the (dark) desktop theme
CHROME_LIGHT_FLAGS="--blink-settings=preferredColorScheme=1,preferredRootScrollbarColorScheme=1"

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

# the dock, in order, Super+1 activates the first one
FAVORITE_APPS=(
  "google-chrome.desktop"
  "org.gnome.Terminal.desktop"
  "com.microsoft.VSCode.desktop"
  "code.desktop" # the name the VS Code deb used to install
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
    pass gnupg pinentry-gnome3 make zsh fontconfig power-profiles-daemon
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

  # the GPG key is only needed to decrypt, cloning the store works without it
  gpg --list-secret-keys "$PASS_GPG_ID" >/dev/null 2>&1 || {
    echo "     [WARN] no secret GPG key for $PASS_GPG_ID, the store will not decrypt" >&2
    echo "            restore it with:  gpg --import <backup.asc> && gpg --edit-key $PASS_GPG_ID trust" >&2
  }

  if [ -d "$PASSWORD_STORE_DIR/.git" ]; then
    sub "password store already cloned, pulling"
    git -C "$PASSWORD_STORE_DIR" pull --quiet --ff-only || echo "     [WARN] could not update the password store" >&2
  elif [ -e "$PASSWORD_STORE_DIR" ]; then
    sub "$PASSWORD_STORE_DIR exists but is not a git clone, leaving it alone"
  elif [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "     [WARN] ~/.ssh/id_ed25519 is missing, skipping the password store clone" >&2
  else
    sub "cloning the password store"
    git clone --quiet "$PASSWORD_STORE_REPO" "$PASSWORD_STORE_DIR" \
      || echo "     [WARN] clone failed, is ~/.ssh/id_ed25519 added to GitHub?" >&2
  fi
}

install_browserpass() {
  log "installing the browserpass native host"

  if [ -x /usr/bin/browserpass-linux64 ]; then
    sub "already installed, skipping"
  else
    sub "downloading browserpass-native $BROWSERPASS_VERSION"
    # subshell so the cleanup trap dies with it instead of leaking into the caller
    (
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      # the release tag carries a leading "v", the asset name does not
      curl -fsSL -o "$tmp/browserpass.tar.gz" \
        "https://github.com/browserpass/browserpass-native/releases/download/v${BROWSERPASS_VERSION}/browserpass-linux64-${BROWSERPASS_VERSION}.tar.gz"
      tar -xzf "$tmp/browserpass.tar.gz" -C "$tmp"

      src="$tmp/browserpass-linux64-${BROWSERPASS_VERSION}"
      make -C "$src" BIN=browserpass-linux64 configure >/dev/null
      sudo make -C "$src" BIN=browserpass-linux64 install >/dev/null
    )
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

  # GTK4 / libadwaita apps (Settings, Files, ...) ignore the gtk-theme setting
  # and only read the user stylesheet, so point that at the theme
  sub "applying the theme to GTK4 apps"
  local gtk4="$HOME/.config/gtk-4.0" css
  mkdir -p "$gtk4"
  # imported rather than symlinked: GTK resolves the theme's url("../assets/...")
  # against the path it loaded, and without the images the window buttons vanish
  rm -f "$gtk4/assets"
  for css in gtk.css gtk-dark.css; do
    rm -f "$gtk4/$css"
    echo "@import url(\"file://$THEME_DIR/gtk-4.0/$css\");" >"$gtk4/$css"
  done
}

install_gnome_extension() {
  # Download and install an extension from extensions.gnome.org for the running shell.
  local uuid="$1"
  local shell_version info url installed available

  shell_version="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
  info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_version}")" || {
    echo "     [WARN] $uuid is not available for GNOME $shell_version" >&2
    return 0
  }

  # an extension built for a newer shell claims to support this one and then
  # dies on a missing API, so go by the version EGO serves for it, not by the
  # directory being there
  available="$(jq -r --arg v "$shell_version" '.shell_version_map[$v].version // empty' <<<"$info")"
  if [ -d "$EXT_DIR/$uuid" ]; then
    installed="$(jq -r '.version // empty' "$EXT_DIR/$uuid/metadata.json" 2>/dev/null || true)"
    if [ -n "$installed" ] && [ "$installed" = "$available" ]; then
      sub "$uuid v$installed already installed, skipping"
      return 0
    fi
    sub "$uuid v${installed:-?} does not match v${available:-?} for GNOME $shell_version, reinstalling"
  fi

  url="https://extensions.gnome.org$(jq -r '.download_url' <<<"$info")"

  sub "installing $uuid"
  # subshell so the cleanup trap dies with it instead of leaking into the caller
  (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/ext.zip" "$url"
    # gnome-extensions takes care of unpacking and compiling the gsettings schemas
    gnome-extensions install --force "$tmp/ext.zip"
  )
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

  # the shell drops the whole list when one entry does not resolve, and VS Code
  # is com.microsoft.VSCode.desktop or code.desktop depending on the build
  local app list=""
  for app in "${FAVORITE_APPS[@]}"; do
    if [ -f "/usr/share/applications/$app" ] || [ -f "$HOME/.local/share/applications/$app" ]; then
      list+="'$app', "
    else
      sub "$app is not installed, leaving it out of the favorites"
    fi
  done

  gsettings set org.gnome.shell favorite-apps "[${list%, }]"
}

configure_zsh() {
  log "setting up zsh"
  # the rest (oh-my-zsh, oh-my-posh, plugins, fzf, mise) is installed by the
  # `update-shell` function that .zshrc defines
  link_config .zshrc
}

install_nerd_font() {
  log "installing the Meslo Nerd Font"

  if fc-list | grep -qi 'Meslo.*Nerd Font'; then
    sub "already present, skipping"
    return 0
  fi

  sub "downloading Meslo.zip"
  mkdir -p "$FONT_DIR"
  # subshell so the cleanup trap dies with it instead of leaking into the caller
  (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    curl -fsSL -o "$tmp/Meslo.zip" "$NERD_FONT_ZIP"
    unzip -qo "$tmp/Meslo.zip" -d "$FONT_DIR" -x 'LICENSE*' 'README*'
  )
  fc-cache -f "$FONT_DIR" >/dev/null
}

configure_default_terminal() {
  log "making gnome-terminal the default terminal"

  # Ubuntu ships zutty, which registers the x-terminal-emulator alternative with
  # the same priority as gnome-terminal and wins the tie, so Ctrl+Alt+T (which
  # launches x-terminal-emulator) ends up opening zutty
  if dpkg -s zutty >/dev/null 2>&1; then
    sub "removing zutty"
    sudo apt-get purge -y -qq zutty
  fi

  sudo update-alternatives --set x-terminal-emulator /usr/bin/gnome-terminal.wrapper >/dev/null
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

configure_chrome_color_scheme() {
  log "reporting a light color scheme to websites"

  local src=/usr/share/applications/google-chrome.desktop
  local dst="$HOME/.local/share/applications/google-chrome.desktop"

  if [ ! -f "$src" ]; then
    sub "Chrome is not installed, skipping"
    return 0
  fi

  # a copy of the packaged entry with the flags injected, regenerated on every
  # run so it does not drift away from the one Chrome ships
  sub "overriding google-chrome.desktop"
  mkdir -p "$(dirname "$dst")"
  sed -E "s|^Exec=/usr/bin/google-chrome-stable|& $CHROME_LIGHT_FLAGS|" "$src" >"$dst"

  command -v update-desktop-database >/dev/null \
    && update-desktop-database "$(dirname "$dst")" >/dev/null 2>&1 || true
}

github_release_asset() {
  # print the download URL of a release asset:
  #   github_release_asset owner/repo latest|<tag> <name regex>
  # the release pages are scraped because api.github.com is rate limited per
  # egress IP, which a corporate network runs into immediately
  local repo="$1" release="$2" pattern="$3" tag="$2" path

  if [ "$release" = "latest" ]; then
    tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" || true)"
    tag="${tag##*/}"
  fi

  path="$(curl -fsSL "https://github.com/$repo/releases/expanded_assets/$tag" \
    | grep -oE "/$repo/releases/download/[^\"]+" \
    | grep -E "$pattern" \
    | awk 'NR == 1' || true)"

  if [ -n "$path" ]; then
    echo "https://github.com$path"
  fi
}

install_fuse2() {
  # AppImages mount themselves with FUSE 2, Ubuntu only ships FUSE 3 by default
  if dpkg -s libfuse2t64 >/dev/null 2>&1 || dpkg -s libfuse2 >/dev/null 2>&1; then
    return 0
  fi
  sub "installing libfuse2"
  sudo apt-get install -y -qq libfuse2t64 2>/dev/null || sudo apt-get install -y -qq libfuse2
}

install_appimaged() {
  log "installing appimaged (AppImage desktop integration)"
  install_fuse2
  mkdir -p "$APPIMAGE_DIR"

  local dst="$APPIMAGE_DIR/appimaged.AppImage" url
  if [ -x "$dst" ]; then
    sub "already installed, skipping"
  else
    # go-appimage only publishes rolling builds, all under the 'continuous' tag
    url="$(github_release_asset probonopd/go-appimage continuous 'appimaged-.*-x86_64\.AppImage$')"
    if [ -z "$url" ]; then
      echo "     [WARN] no appimaged build found, skipping" >&2
      return 0
    fi
    sub "downloading ${url##*/}"
    curl -fsSL -o "$dst" "$url"
    chmod +x "$dst"
  fi

  sub "enabling the appimaged user service"
  mkdir -p "$HOME/.config/systemd/user"
  cat >"$HOME/.config/systemd/user/appimaged.service" <<EOF
[Unit]
Description=AppImage desktop integration daemon
After=graphical-session.target

[Service]
ExecStart=$dst
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now appimaged.service
}

install_logseq() {
  log "installing the Logseq OG AppImage"
  mkdir -p "$APPIMAGE_DIR"

  # logseq/logseq now ships the DB version, the file-based app lives on in logseq/og
  local url name
  url="$(github_release_asset logseq/og latest 'Logseq-OG-linux-x64-.*\.AppImage$')"
  if [ -z "$url" ]; then
    echo "     [WARN] no Logseq OG release found, skipping" >&2
    return 0
  fi

  name="${url##*/}"
  if [ -x "$APPIMAGE_DIR/$name" ]; then
    sub "$name already installed"
  else
    sub "downloading $name"
    curl -fsSL -o "$APPIMAGE_DIR/$name.part" "$url"
    mv "$APPIMAGE_DIR/$name.part" "$APPIMAGE_DIR/$name"
    chmod +x "$APPIMAGE_DIR/$name"
  fi

  sub "removing older versions and the DB build"
  find "$APPIMAGE_DIR" -maxdepth 1 -name 'Logseq-*.AppImage' ! -name "$name" -delete
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
  configure_zsh
  install_nerd_font
  configure_default_terminal
  configure_terminal
  configure_chrome_color_scheme
  install_appimaged
  install_logseq
  install_pass
  install_browserpass

  echo
  echo " => done, log out and back in for the shell theme and extensions to load"
  echo "    then run 'update-shell' in a zsh session to install oh-my-zsh / oh-my-posh"
}

main "$@"
