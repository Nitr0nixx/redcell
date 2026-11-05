#!/usr/bin/env bash
# lib/theme.sh — bascule et restauration du thème Omarchy.
# Dépend de lib/common.sh (déjà sourcé par bin/pentest).

# Lit le slug du thème actuellement appliqué.
# Source fiable : ~/.local/state/omarchy/current/theme.name (écrit par omarchy-theme-set).
theme_current() {
  local f="$XDG_STATE_HOME/omarchy/current/theme.name"
  if [[ -f "$f" ]]; then
    tr -d '[:space:]' < "$f"
  elif command -v omarchy >/dev/null 2>&1; then
    # Repli : normalise la sortie (minuscules, espaces -> tirets) comme theme-set.
    omarchy theme current 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
  else
    printf ''
  fi
}

# Applique un thème par son slug (ex. "pentest", "neon-city").
theme_apply() {
  local slug="$1"
  [[ -n "$slug" ]] || { err "theme_apply : slug vide"; return 1; }
  if ! command -v omarchy >/dev/null 2>&1; then
    warn "commande 'omarchy' introuvable — thème non appliqué"
    return 0
  fi
  run omarchy theme set "$slug"
}

# Vérifie qu'un thème (user ou stock) existe pour ce slug.
theme_exists() {
  local slug="$1"
  [[ -d "$XDG_CONFIG_HOME/omarchy/themes/$slug" ]] && return 0
  [[ -d "${OMARCHY_PATH:-/usr/share/omarchy}/themes/$slug" ]] && return 0
  return 1
}
