#!/usr/bin/env bash
# lib/common.sh — fondations partagées : chemins, logs, config, état.
# Sourcé par bin/pentest et les autres modules. Aucune action au chargement.

# --- Mode strict -------------------------------------------------------------
# errexit + nounset + pipefail : on veut échouer tôt et proprement.
set -euo pipefail

# --- Chemins standards (XDG) -------------------------------------------------
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

PENTEST_CONFIG_DIR="$XDG_CONFIG_HOME/mode-pentest"
PENTEST_CONFIG_FILE="$PENTEST_CONFIG_DIR/config.toml"
PENTEST_STATE_DIR="$XDG_STATE_HOME/mode-pentest"

# Fichiers d'état :
#   active        -> présent quand le mode est actif ; contient le nom du lab.
#   previous.env  -> état d'AVANT activation (thème, DND) pour restauration.
PENTEST_ACTIVE_FILE="$PENTEST_STATE_DIR/active"
PENTEST_PREVIOUS_FILE="$PENTEST_STATE_DIR/previous.env"

# Dry-run : si PENTEST_DRY_RUN=1, les actions système sont affichées, pas
# exécutées. Les fichiers d'état sont tout de même écrits (utile pour les tests).
: "${PENTEST_DRY_RUN:=0}"

# --- Journalisation ----------------------------------------------------------
_c_reset=$'\e[0m'; _c_red=$'\e[31m'; _c_grn=$'\e[32m'; _c_ylw=$'\e[33m'; _c_dim=$'\e[2m'
# Pas de couleur si la sortie n'est pas un terminal.
if [[ ! -t 1 ]]; then _c_reset=""; _c_red=""; _c_grn=""; _c_ylw=""; _c_dim=""; fi

log()  { printf '%s[pentest]%s %s\n' "$_c_dim" "$_c_reset" "$*"; }
ok()   { printf '%s[pentest]%s %s\n' "$_c_grn" "$_c_reset" "$*"; }
warn() { printf '%s[pentest]%s %s\n' "$_c_ylw" "$_c_reset" "$*" >&2; }
err()  { printf '%s[pentest]%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }

# run : exécute une commande, ou l'affiche seulement en dry-run.
run() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$_c_dim" "$_c_reset" "$*"
    return 0
  fi
  "$@"
}

# runq : comme run, mais en exécution réelle la sortie de la commande est
# silencieuse (utile pour hyprctl qui affiche "ok"). En dry-run, on l'affiche.
runq() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$_c_dim" "$_c_reset" "$*"
    return 0
  fi
  "$@" >/dev/null 2>&1
}

# --- Lecture de config (TOML plat, clé = "valeur") ---------------------------
# Lecteur minimal volontairement simple : suffisant pour un fichier plat.
# Usage : cfg_get <clé> <valeur_par_défaut>
cfg_get() {
  local key="$1" default="${2:-}" line value
  [[ -f "$PENTEST_CONFIG_FILE" ]] || { printf '%s' "$default"; return 0; }
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$PENTEST_CONFIG_FILE" 2>/dev/null | head -1 || true)
  [[ -n "$line" ]] || { printf '%s' "$default"; return 0; }
  value=${line#*=}
  # Retire espaces, guillemets et commentaire de fin.
  value=$(printf '%s' "$value" | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//')
  [[ -n "$value" ]] && printf '%s' "$value" || printf '%s' "$default"
}

# --- Helpers d'état ----------------------------------------------------------
ensure_state_dir() { mkdir -p "$PENTEST_STATE_DIR"; }

is_active() { [[ -f "$PENTEST_ACTIVE_FILE" ]]; }

active_lab() { [[ -f "$PENTEST_ACTIVE_FILE" ]] && cat "$PENTEST_ACTIVE_FILE" || printf ''; }

# Écrit une variable dans previous.env (clé=valeur, échappée simplement).
save_previous() {
  local key="$1" val="$2"
  ensure_state_dir
  touch "$PENTEST_PREVIOUS_FILE"
  # Retire une éventuelle ligne existante pour cette clé, puis ajoute.
  grep -v -E "^${key}=" "$PENTEST_PREVIOUS_FILE" > "$PENTEST_PREVIOUS_FILE.tmp" 2>/dev/null || true
  mv "$PENTEST_PREVIOUS_FILE.tmp" "$PENTEST_PREVIOUS_FILE"
  printf '%s=%q\n' "$key" "$val" >> "$PENTEST_PREVIOUS_FILE"
}

# Lit une variable de previous.env (vide si absente).
load_previous() {
  local key="$1"
  [[ -f "$PENTEST_PREVIOUS_FILE" ]] || { printf ''; return 0; }
  # shellcheck disable=SC1090
  ( set +u; source "$PENTEST_PREVIOUS_FILE" 2>/dev/null; printf '%s' "${!key:-}" )
}
