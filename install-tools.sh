#!/usr/bin/env bash
# Personal terminal tools. No system packages or project files are modified.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTFILES/versions.env"
export PATH="$HOME/.local/bin:$PATH"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-tools"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-tools"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-downloads"
log() { printf '[tools] %s\n' "$*"; }
die() { printf '[tools:error] %s\n' "$*" >&2; exit 1; }
for tool in curl sha256sum python3; do
  command -v "$tool" >/dev/null || die "$tool fehlt. Bitte zuerst installieren."
done
[[ "$(uname -s)" == Linux ]] || die 'Automatische Tool-Installation unterstützt derzeit Linux.'
case "$(uname -m)" in
  x86_64) arch=x86_64; herdr_sha="$HERDR_LINUX_X86_64_SHA256" ;;
  aarch64|arm64) arch=aarch64; herdr_sha="$HERDR_LINUX_AARCH64_SHA256" ;;
  *) die 'Keine geprüften Release-Assets für diese Architektur.' ;;
esac
mkdir -p "$HOME/.local/bin" "$data_home" "$state_home" "$cache_home"
scratch="$(mktemp -d "$data_home/.install.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

checksum() { sha256sum "$1" | cut -d ' ' -f 1; }
download() {
  local url="$1" expected="$2" target="$3"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "Ungültige SHA-256-Prüfsumme: $target"
  if [[ -f "$target" && "$(checksum "$target")" == "$expected" ]]; then return; fi
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 300 \
    "$url" -o "$scratch/download"
  [[ "$(checksum "$scratch/download")" == "$expected" ]] || die "Download-Prüfsumme stimmt nicht: $url"
  mv "$scratch/download" "$target"
}

# Back up first adoption; refuse to overwrite subsequently edited managed copies.
copy_config() {
  local source="$1" target="$2" key="$3" previous
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -f "$target" ]] || die "Keine reguläre Konfiguration: $target"
    if cmp -s "$source" "$target"; then
      checksum "$target" > "$state_home/$key.sha256"
      return
    fi
    if [[ -f "$state_home/$key.sha256" ]]; then
      previous="$(cat "$state_home/$key.sha256")"
      [[ "$(checksum "$target")" == "$previous" ]] || die "Lokal bearbeitet, bleibt unverändert: $target"
    fi
    cp -pL "$target" "$target.bak.$(date +%Y%m%d%H%M%S).$$"
    log "Backup angelegt: $target"
  fi
  mkdir -p "$(dirname "$target")"
  cp "$source" "$scratch/config"
  chmod 600 "$scratch/config"
  mv -f "$scratch/config" "$target"
  checksum "$target" > "$state_home/$key.sha256"
  log "Konfiguration: $target"
}

# Use an existing Nano. Otherwise extract the distro's authenticated APT package
# into the personal home; shared ncurses libraries must already be available.
if ! command -v nano >/dev/null; then
  command -v apt-get >/dev/null && command -v dpkg-deb >/dev/null \
    || die 'Nano fehlt. Automatisches Entpacken benötigt apt-get und dpkg-deb.'
  [[ ! -e "$HOME/.local/bin/nano" && ! -L "$HOME/.local/bin/nano" ]] || die 'Ziel für Nano ist belegt.'
  [[ ! -e "$data_home/nano" ]] || die "Unvollständige Nano-Installation: $data_home/nano"
  (cd "$scratch" && apt-get download nano)
  packages=("$scratch"/nano_*.deb)
  [[ ${#packages[@]} == 1 && -f "${packages[0]}" ]] || die 'Kein eindeutiges Nano-Paket erhalten.'
  dpkg-deb -x "${packages[0]}" "$scratch/nano"
  "$scratch/nano/usr/bin/nano" --version >/dev/null \
    || die 'Nano kann nicht starten; benötigte Systembibliotheken fehlen.'
  mv "$scratch/nano" "$data_home/nano"
  ln -s "$data_home/nano/usr/bin/nano" "$HOME/.local/bin/nano"
  log 'Nano im persönlichen Home installiert.'
fi

if command -v herdr >/dev/null; then
  [[ "$(herdr --version)" == "herdr $HERDR_VERSION" ]] \
    || die 'Vorhandene Herdr-Version weicht vom Pin ab; kein automatisches Überschreiben.'
  log "Herdr $HERDR_VERSION bereits vorhanden."
else
  [[ ! -e "$HOME/.local/bin/herdr" && ! -L "$HOME/.local/bin/herdr" ]] || die 'Ziel für Herdr ist belegt.'
  asset="herdr-linux-$arch"
  download "https://github.com/herdrdev/herdr/releases/download/v$HERDR_VERSION/$asset" \
    "$herdr_sha" "$cache_home/$asset-$HERDR_VERSION"
  install -m 755 "$cache_home/$asset-$HERDR_VERSION" "$scratch/herdr"
  [[ "$("$scratch/herdr" --version)" == "herdr $HERDR_VERSION" ]] || die 'Herdr-Binary kann nicht starten.'
  mv "$scratch/herdr" "$HOME/.local/bin/herdr"
fi

if command -v broot >/dev/null; then
  [[ "$(broot --version)" == "broot $BROOT_VERSION" ]] \
    || die 'Vorhandene Broot-Version weicht vom Pin ab; kein automatisches Überschreiben.'
  log "Broot $BROOT_VERSION bereits vorhanden."
else
  [[ ! -e "$HOME/.local/bin/broot" && ! -L "$HOME/.local/bin/broot" ]] || die 'Ziel für Broot ist belegt.'
  archive="$cache_home/broot_$BROOT_VERSION.zip"
  download "https://github.com/Canop/broot/releases/download/v$BROOT_VERSION/broot_$BROOT_VERSION.zip" \
    "$BROOT_ARCHIVE_SHA256" "$archive"
  python3 - "$archive" "$arch-unknown-linux-musl/broot" "$scratch/broot" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    with open(sys.argv[3], 'wb') as target:
        target.write(archive.read(sys.argv[2]))
PY
  chmod 755 "$scratch/broot"
  [[ "$("$scratch/broot" --version)" == "broot $BROOT_VERSION" ]] || die 'Broot-Binary kann nicht starten.'
  mv "$scratch/broot" "$HOME/.local/bin/broot"
fi

# Nano includes only syntax definitions, so concatenate settings into one nanorc.
cat "$DOTFILES/nano/nanorc" > "$scratch/nanorc"
syntax_dir=/usr/share/nano
if [[ "$(readlink -f "$(command -v nano)")" == "$data_home/nano/usr/bin/nano" ]]; then
  syntax_dir="$data_home/nano/usr/share/nano"
fi
if compgen -G "$syntax_dir/*.nanorc" >/dev/null; then
  printf '\n# Includes\ninclude "%s/*.nanorc"\n' "$syntax_dir" >> "$scratch/nanorc"
fi
if [[ ! -f /.dockerenv ]] && command -v clip.exe >/dev/null; then
  printf '\n' >> "$scratch/nanorc"
  cat "$DOTFILES/nano/wsl.nanorc" >> "$scratch/nanorc"
fi
copy_config "$scratch/nanorc" "$HOME/.nanorc" nano
copy_config "$DOTFILES/herdr/config.toml" "$config_home/herdr/config.toml" herdr

# Keep existing Broot configurations (including Hjson and imported skins/verbs).
if [[ -f "$state_home/broot.sha256" || ! -d "$config_home/broot" ]]; then
  copy_config "$DOTFILES/broot/conf.toml" "$config_home/broot/conf.toml" broot
fi
if [[ ! -r "$config_home/broot/launcher/bash/br" ]]; then
  mkdir -p "$config_home/broot/launcher/bash"
  broot --print-shell-function bash > "$scratch/br"
  copy_config "$scratch/br" "$config_home/broot/launcher/bash/br" broot-launcher
  broot --set-install-state installed
fi
HERDR_CONFIG_PATH="$config_home/herdr/config.toml" herdr config check
log 'Fertig. Ein neues zsh-Terminal öffnen; Herdr mit herdr starten.'
