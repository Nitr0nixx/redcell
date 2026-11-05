#!/usr/bin/env bash
# lib/notify.sh — mode "ne pas déranger" (DND) du shell Omarchy (Quickshell).
# On limite les notifications aux alertes importantes en activant le DND :
# les notifications non critiques sont silencieuses tant que le mode est actif.
# Dépend de lib/common.sh.

# Lit l'état du DND : "on" ou "off".
dnd_state() {
  if command -v omarchy-shell >/dev/null 2>&1; then
    local s
    s=$(omarchy-shell notifications isDnd 2>/dev/null | tr -d '[:space:]' || true)
    case "$s" in on|off) printf '%s' "$s" ;; *) printf 'off' ;; esac
  else
    printf 'off'
  fi
}

# Bascule le DND (le shell n'expose qu'un toggle).
_dnd_toggle() {
  command -v omarchy-shell >/dev/null 2>&1 || { warn "omarchy-shell introuvable — DND ignoré"; return 0; }
  run omarchy-shell notifications toggleDnd
}

# Force le DND à l'état voulu ("on"/"off"), de façon idempotente.
dnd_set() {
  local want="$1" cur
  cur=$(dnd_state)
  # En dry-run, dnd_state renvoie l'état réel ; on affiche juste l'intention.
  if [[ "$cur" == "$want" ]]; then
    log "DND déjà '$want'"
    return 0
  fi
  _dnd_toggle
}
