#!/usr/bin/env bash
# install.sh — déploie (ou retire) le mode pentest sur ce système.
#
#   ./install.sh               installe (indicateur de barre compris)
#   ./install.sh --no-bar      installe sans toucher à la barre (shell.json)
#   ./install.sh --uninstall   désinstalle
#
# Écrit HORS du projet (liens symboliques + shell.json). Idempotent.
# N'installe AUCUN paquet. Sauvegarde shell.json avant de le modifier.

set -euo pipefail

ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

: "${XDG_CONFIG_HOME:=$HOME/.config}"
BIN_DIR="$HOME/.local/bin"
THEME_TARGET="$XDG_CONFIG_HOME/omarchy/themes/pentest"
PLUGIN_TARGET="$XDG_CONFIG_HOME/omarchy/plugins/theo.pentest"
CONFIG_DIR="$XDG_CONFIG_HOME/mode-pentest"
SHELL_JSON="$XDG_CONFIG_HOME/omarchy/shell.json"
WIDGET_ID="theo.pentest"

link() { # link <src> <dst>
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    echo "  = déjà lié : $dst"
  else
    ln -snf "$src" "$dst"; echo "  + lié : $dst"
  fi
}

copy_if_absent() { # copy_if_absent <src> <dst>
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then echo "  = conservé : $dst"
  else cp "$src" "$dst"; echo "  + créé : $dst"; fi
}

# Ajoute/retire le widget de barre dans shell.json (python3, avec sauvegarde).
wire_bar() { # wire_bar <add|remove>
  local action="$1"
  [[ -f "$SHELL_JSON" ]] || { echo "  ⚠ $SHELL_JSON absent — barre non modifiée."; return 0; }
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  ⚠ python3 absent — ajoute '$WIDGET_ID' à la main dans shell.json."; return 0
  fi
  cp "$SHELL_JSON" "$SHELL_JSON.bak.$(date +%s)"
  python3 - "$SHELL_JSON" "$action" "$WIDGET_ID" <<'PY'
import json, sys
path, action, wid = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: data = json.load(f)
layout = data.setdefault("bar", {}).setdefault("layout", {})
right = layout.setdefault("right", [])
def has(): return any(isinstance(e, dict) and e.get("id") == wid for e in right)
if action == "add":
    if not has():
        # Insère juste avant le tray si présent, sinon en tête de "right".
        idx = next((i for i,e in enumerate(right) if isinstance(e,dict) and e.get("id")=="omarchy.tray"), 0)
        right.insert(idx, {"id": wid})
        print("  + widget ajouté à la barre (section right)")
    else:
        print("  = widget déjà dans la barre")
else:
    before = len(right)
    layout["right"] = [e for e in right if not (isinstance(e,dict) and e.get("id")==wid)]
    print("  - widget retiré de la barre" if len(layout["right"])!=before else "  = widget absent de la barre")
with open(path, "w") as f: json.dump(data, f, indent=2); f.write("\n")
PY
}

install_mode() {
  local with_bar="$1"
  echo "Installation du mode pentest…"
  link "$ROOT_DIR/bin/pentest"         "$BIN_DIR/pentest"
  link "$ROOT_DIR/bin/pentest-browser" "$BIN_DIR/pentest-browser"
  link "$ROOT_DIR/themes/pentest"      "$THEME_TARGET"
  link "$ROOT_DIR/shell-plugin/theo.pentest" "$PLUGIN_TARGET"

  mkdir -p "$CONFIG_DIR"
  copy_if_absent "$ROOT_DIR/config/mode-pentest.example.toml" "$CONFIG_DIR/config.toml"
  copy_if_absent "$ROOT_DIR/config/layout.conf"               "$CONFIG_DIR/layout.conf"
  # Modèles de lab personnalisables (sinon ceux du projet sont utilisés).
  mkdir -p "$CONFIG_DIR/templates"
  for t in scope notes report; do
    copy_if_absent "$ROOT_DIR/templates/$t.md" "$CONFIG_DIR/templates/$t.md"
  done

  if [[ "$with_bar" == "1" ]]; then
    echo "Barre :"; wire_bar add
    command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi

  echo
  echo "Terminé.  pentest status"
  case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "  ⚠ $BIN_DIR n'est pas dans ton PATH." ;; esac
}

uninstall_mode() {
  echo "Désinstallation du mode pentest…"
  echo "Barre :"; wire_bar remove
  for l in "$BIN_DIR/pentest" "$BIN_DIR/pentest-browser" "$THEME_TARGET" "$PLUGIN_TARGET"; do
    [[ -L "$l" ]] && { rm -f "$l"; echo "  - $l"; }
  done
  command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "  = config conservée : $CONFIG_DIR (supprime-la à la main si besoin)"
  echo "Note : lance 'pentest off' avant si le mode est encore actif."
}

case "${1:-}" in
  --uninstall|-u) uninstall_mode ;;
  --no-bar)       install_mode 0 ;;
  ""|--install)   install_mode 1 ;;
  *) echo "Usage: $0 [--install|--no-bar|--uninstall]"; exit 2 ;;
esac
