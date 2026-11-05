#!/usr/bin/env bash
# install.sh — déploie (ou retire) le mode pentest sur ce système.
#
#   ./install.sh            installe
#   ./install.sh --uninstall  désinstalle
#
# Ce script écrit HORS du projet (liens symboliques). Il est idempotent :
# le relancer ne casse rien. Il n'installe AUCUN paquet.

set -euo pipefail

ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

: "${XDG_CONFIG_HOME:=$HOME/.config}"
BIN_TARGET="$HOME/.local/bin/pentest"
THEME_TARGET="$XDG_CONFIG_HOME/omarchy/themes/pentest"
CONFIG_DIR="$XDG_CONFIG_HOME/mode-pentest"
CONFIG_FILE="$CONFIG_DIR/config.toml"

link() { # link <src> <dst> : lien symbolique idempotent
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    echo "  = déjà lié : $dst"
  else
    ln -snf "$src" "$dst"
    echo "  + lié : $dst -> $src"
  fi
}

install_mode() {
  echo "Installation du mode pentest…"
  link "$ROOT_DIR/bin/pentest" "$BIN_TARGET"
  link "$ROOT_DIR/themes/pentest" "$THEME_TARGET"

  mkdir -p "$CONFIG_DIR"
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "  = config déjà présente, conservée : $CONFIG_FILE"
  else
    cp "$ROOT_DIR/config/mode-pentest.example.toml" "$CONFIG_FILE"
    echo "  + config créée : $CONFIG_FILE"
  fi

  echo
  echo "Terminé. Vérifie que ~/.local/bin est dans ton PATH, puis :"
  echo "  pentest status"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) echo "  ⚠  ~/.local/bin n'est pas dans ton PATH." ;;
  esac
}

uninstall_mode() {
  echo "Désinstallation du mode pentest…"
  [[ -L "$BIN_TARGET" ]] && { rm -f "$BIN_TARGET"; echo "  - $BIN_TARGET"; }
  [[ -L "$THEME_TARGET" ]] && { rm -f "$THEME_TARGET"; echo "  - $THEME_TARGET"; }
  echo "  = config conservée : $CONFIG_FILE (supprime-la à la main si tu veux)"
  echo "Note : relance 'pentest off' avant si le mode est encore actif."
}

case "${1:-}" in
  --uninstall|-u) uninstall_mode ;;
  ""|--install)   install_mode ;;
  *) echo "Usage: $0 [--install|--uninstall]"; exit 2 ;;
esac
