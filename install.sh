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
BINDINGS="$XDG_CONFIG_HOME/hypr/bindings.lua"
BIND_KEY="SUPER + SHIFT + ALT + P"

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

# Ajoute/retire le raccourci clavier dans bindings.lua (bloc balisé + sauvegarde).
wire_binding() { # wire_binding <add|remove>
  local action="$1"
  [[ -f "$BINDINGS" ]] || { echo "  ⚠ $BINDINGS absent — raccourci non géré."; return 0; }
  local begin="-- >>> mode-pentest >>>" end="-- <<< mode-pentest <<<"
  if grep -qF -- "$begin" "$BINDINGS"; then
    sed -i "/$begin/,/$end/d" "$BINDINGS"   # retire un bloc existant (idempotent)
  fi
  if [[ "$action" == "add" ]]; then
    cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
    {
      echo "$begin  (géré par mode-pentest/install.sh)"
      echo "o.bind(\"$BIND_KEY\", \"Pentest mode toggle\", \"pentest-toggle\")"
      echo "$end"
    } >> "$BINDINGS"
    echo "  + raccourci $BIND_KEY -> pentest-toggle"
  else
    echo "  - raccourci retiré"
  fi
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
}

install_mode() {
  local with_bar="$1"
  echo "Installation du mode pentest…"
  link "$ROOT_DIR/bin/pentest"         "$BIN_DIR/pentest"
  link "$ROOT_DIR/bin/pentest-browser" "$BIN_DIR/pentest-browser"
  link "$ROOT_DIR/bin/pentest-toggle"  "$BIN_DIR/pentest-toggle"
  link "$ROOT_DIR/themes/pentest"      "$THEME_TARGET"
  link "$ROOT_DIR/shell-plugin/theo.pentest" "$PLUGIN_TARGET"

  mkdir -p "$CONFIG_DIR"
  copy_if_absent "$ROOT_DIR/config/mode-pentest.example.toml" "$CONFIG_DIR/config.toml"
  copy_if_absent "$ROOT_DIR/config/layout.conf"               "$CONFIG_DIR/layout.conf"
  copy_if_absent "$ROOT_DIR/config/tools.list"                "$CONFIG_DIR/tools.list"
  copy_if_absent "$ROOT_DIR/config/menu-apps.list"            "$CONFIG_DIR/menu-apps.list"
  copy_if_absent "$ROOT_DIR/config/menu-keep.list"            "$CONFIG_DIR/menu-keep.list"
  copy_if_absent "$ROOT_DIR/config/vuln-rules.txt"            "$CONFIG_DIR/vuln-rules.txt"
  # Modèles de lab personnalisables (sinon ceux du projet sont utilisés).
  mkdir -p "$CONFIG_DIR/templates"
  for t in scope notes report; do
    copy_if_absent "$ROOT_DIR/templates/$t.md" "$CONFIG_DIR/templates/$t.md"
  done

  echo "Raccourci :"; wire_binding add

  if [[ "$with_bar" == "1" ]]; then
    echo "Barre :"; wire_bar add
    command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi

  # Menu : établit l'état de base (apps cyber masquées hors mode ; si le mode
  # est déjà actif, on révèle/focalise à la place). Rien si menu_integration=off.
  echo "Menu :"; "$BIN_DIR/pentest" menu reconcile >/dev/null 2>&1 \
    && echo "  = lanceur d'applications adapté au mode" \
    || echo "  = (menu non modifié)"

  echo
  echo "Terminé.  pentest status"
  case ":$PATH:" in *":$BIN_DIR:"*) : ;; *) echo "  ⚠ $BIN_DIR n'est pas dans ton PATH." ;; esac
}

uninstall_mode() {
  echo "Désinstallation du mode pentest…"
  # Menu : retire TOUTES nos interventions (ombres + éditions en place) AVANT de
  # retirer le lien 'pentest', pour rendre le lanceur à son état d'origine.
  echo "Menu :"; [[ -x "$BIN_DIR/pentest" ]] && { "$BIN_DIR/pentest" menu reveal-all >/dev/null 2>&1 \
    && echo "  - interventions sur le menu annulées" || echo "  = (rien à annuler)"; }
  echo "Raccourci :"; wire_binding remove
  echo "Barre :"; wire_bar remove
  for l in "$BIN_DIR/pentest" "$BIN_DIR/pentest-browser" "$BIN_DIR/pentest-toggle" "$THEME_TARGET" "$PLUGIN_TARGET"; do
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
