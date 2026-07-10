#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }

# ── oh-my-zsh (im devcontainer meist schon da) ──
if [ ! -d "$ZSH_DIR" ]; then
  log "installiere oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ── externe Plugins & Theme ──
clone_if_missing() {
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    log "vorhanden: $(basename "$dest")"
  else
    log "clone: $(basename "$dest")"
    git clone --depth=1 "https://github.com/$repo" "$dest"
  fi
}

mkdir -p "$CUSTOM/plugins" "$CUSTOM/themes"
clone_if_missing romkatv/powerlevel10k            "$CUSTOM/themes/powerlevel10k"
clone_if_missing zsh-users/zsh-autosuggestions    "$CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing zsh-users/zsh-syntax-highlighting "$CUSTOM/plugins/zsh-syntax-highlighting"

# ── Symlinks ──
link() {
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    [ -L "$dst" ] || mv "$dst" "$dst.bak.$(date +%s)"
  fi
  ln -sfn "$src" "$dst"
  log "link: $dst -> $src"
}

link "$DOTFILES/zsh/zshrc"    "$HOME/.zshrc"
link "$DOTFILES/zsh/p10k.zsh" "$HOME/.p10k.zsh"

log "fertig"
