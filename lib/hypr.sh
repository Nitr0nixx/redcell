#!/usr/bin/env bash
# lib/hypr.sh — gestion des espaces de travail Hyprland pour le mode pentest.
# Ouvre la disposition décrite dans layout.conf et sait la refermer proprement
# (uniquement NOS fenêtres, repérées par leur app-id dédié).
# Dépend de lib/common.sh.

# Fichier de disposition : config utilisateur si présent, sinon modèle du projet.
layout_file() {
  local user="$PENTEST_CONFIG_DIR/layout.conf"
  if [[ -f "$user" ]]; then printf '%s' "$user"
  else printf '%s' "$ROOT_DIR/config/layout.conf"; fi
}

hypr_available() { command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; }

# Fichier d'état listant les app-id que NOUS avons ouverts (pour la fermeture).
_appids_file() { printf '%s' "$PENTEST_STATE_DIR/layout.appids"; }

# Ouvre la disposition pour un lab donné.
hypr_open_layout() {
  local lab="$1" first_ws="" ws appid cmd line
  if ! hypr_available; then
    warn "Hyprland indisponible (hyprctl) — disposition non ouverte."
    return 0
  fi
  ensure_state_dir
  : > "$(_appids_file)"   # repart d'une liste vide

  while IFS='|' read -r ws appid cmd; do
    # Ignore commentaires et lignes vides.
    [[ -z "${ws// }" || "${ws#\#}" != "$ws" ]] && continue
    ws=$(printf '%s' "$ws" | tr -d '[:space:]')
    appid=$(printf '%s' "$appid" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    cmd=$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$ws" && -n "$cmd" ]] || continue
    cmd=${cmd//\{LAB\}/$lab}
    [[ -z "$first_ws" ]] && first_ws="$ws"

    log "ouverture [$ws] $appid : $cmd"
    # Placement idiomatique Hyprland : règle one-shot [workspace N silent].
    runq hyprctl dispatch exec "[workspace $ws silent] $cmd"
    [[ -n "$appid" ]] && printf '%s\n' "$appid" >> "$(_appids_file)"
  done < "$(layout_file)"

  # Focalise le premier espace de travail de la disposition.
  [[ -n "$first_ws" ]] && runq hyprctl dispatch workspace "$first_ws" || true
}

# Ferme UNIQUEMENT les fenêtres que nous avons ouvertes (par app-id).
# tmux survit (serveur détaché) : aucune perte de travail côté terminal.
hypr_close_layout() {
  local appid f
  f="$(_appids_file)"
  if ! hypr_available; then rm -f "$f"; return 0; fi
  [[ -f "$f" ]] || return 0
  while read -r appid; do
    [[ -n "$appid" ]] || continue
    log "fermeture des fenêtres 'class:$appid'…"
    # Boucle : il peut y avoir plusieurs fenêtres de même classe.
    runq hyprctl dispatch closewindow "class:$appid" || true
  done < "$f"
  rm -f "$f"
}
