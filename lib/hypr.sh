#!/usr/bin/env bash
# lib/hypr.sh — gestion des espaces de travail Hyprland pour le mode pentest.
# Ouvre la disposition décrite dans layout.conf et sait la refermer proprement
# (uniquement NOS fenêtres, repérées par leur app-id dédié).
#
# IMPORTANT : cet Hyprland est configuré en Lua, donc « hyprctl dispatch X » est
# interprété comme hl.dispatch(X). On utilise donc les dispatchers Lua :
#   exec   -> hl.dsp.exec_cmd("[workspace N silent] cmd")
#   focus  -> hl.dsp.focus({ workspace = "N" })
#   close  -> hl.dsp.window.close({ window = "class:APPID" })
# Dépend de lib/common.sh.

# Fichier de disposition : config utilisateur si présent, sinon modèle du projet.
layout_file() {
  local user="$PENTEST_CONFIG_DIR/layout.conf"
  if [[ -f "$user" ]]; then printf '%s' "$user"
  else printf '%s' "$ROOT_DIR/config/layout.conf"; fi
}

hypr_available() { command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; }

# Échappe une chaîne pour l'insérer dans une chaîne Lua entre guillemets doubles.
_lua_escape() { local s="$1"; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

# Fichier d'état listant les app-id que NOUS avons ouverts (pour la fermeture).
_appids_file() { printf '%s' "$PENTEST_STATE_DIR/layout.appids"; }

# Ouvre la disposition pour un lab donné.
hypr_open_layout() {
  local lab="$1" first_ws="" ws appid cmd line esc
  if ! hypr_available; then
    warn "Hyprland indisponible (hyprctl) — disposition non ouverte."
    return 0
  fi
  ensure_state_dir
  : > "$(_appids_file)"   # repart d'une liste vide

  while IFS='|' read -r ws appid cmd; do
    [[ -z "${ws// }" || "${ws#\#}" != "$ws" ]] && continue
    ws=$(printf '%s' "$ws" | tr -d '[:space:]')
    appid=$(printf '%s' "$appid" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    cmd=$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$ws" && -n "$cmd" ]] || continue
    cmd=${cmd//\{LAB\}/$lab}
    [[ -z "$first_ws" ]] && first_ws="$ws"

    log "ouverture [$ws] $appid : $cmd"
    # Dispatcher Lua exec_cmd avec la règle one-shot [workspace N silent].
    esc=$(_lua_escape "[workspace $ws silent] $cmd")
    runq hyprctl dispatch "hl.dsp.exec_cmd(\"$esc\")"
    [[ -n "$appid" ]] && printf '%s\n' "$appid" >> "$(_appids_file)"
  done < "$(layout_file)"

  # Focalise le premier espace de travail de la disposition.
  [[ -n "$first_ws" ]] && runq hyprctl dispatch "hl.dsp.focus({ workspace = \"$first_ws\" })" || true
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
    if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
      run hyprctl dispatch "hl.dsp.window.close({ window = \"class:$appid\" })"
    else
      # Ferme toutes les fenêtres de cette classe (plafonné pour rester sûr).
      local n=0
      while hyprctl clients -j 2>/dev/null | jq -e --arg c "$appid" 'any(.[]; .class==$c)' >/dev/null 2>&1; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"class:$appid\" })" >/dev/null 2>&1 || true
        n=$((n+1)); [[ $n -ge 10 ]] && break
        sleep 0.2
      done
    fi
  done < "$f"
  rm -f "$f"
}
