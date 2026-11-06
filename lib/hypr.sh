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

# ---------------------------------------------------------------------------
# Fermeture de TOUTES les fenêtres ouvertes pendant le mode pentest.
# Principe : à l'activation on photographie les fenêtres existantes (adresses
# Hyprland) ; à la sortie on ferme toutes celles qui n'y figuraient pas.
# Les fenêtres d'avant le mode ne sont jamais touchées. Fermeture « douce »
# (comme SUPER+W) : une app peut demander confirmation (ex. onglets Firefox).
# ---------------------------------------------------------------------------
_windows_snapshot_file() { printf '%s' "$PENTEST_STATE_DIR/windows.before"; }

# Photographie les fenêtres présentes (à appeler à la 1re activation).
hypr_snapshot_windows() {
  ensure_state_dir
  local f; f="$(_windows_snapshot_file)"
  if ! hypr_available || [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    [[ "$PENTEST_DRY_RUN" == "1" ]] && printf '%s[dry-run]%s photographierait les fenêtres ouvertes\n' "$_c_dim" "$_c_reset"
    : > "$f"; return 0
  fi
  hyprctl clients -j 2>/dev/null | jq -r '.[].address' > "$f" 2>/dev/null || : > "$f"
  log "fenêtres d'avant le mode mémorisées ($(wc -l < "$f"))."
}

# Adresse de la fenêtre qui héberge CE processus (terminal d'où l'on lance
# « pentest off »), vide sinon. On remonte les parents jusqu'à un pid de fenêtre.
_caller_window() {
  local clients="$1" p=$$ addr
  while [[ -n "$p" && "$p" -gt 1 ]]; do
    addr=$(jq -r --argjson p "$p" 'first(.[] | select(.pid==$p) | .address) // empty' <<<"$clients")
    [[ -n "$addr" ]] && { printf '%s' "$addr"; return 0; }
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
  return 0
}

# Ferme les fenêtres nées pendant le mode, SAUF celle de l'appelant.
# Écrit l'adresse de l'appelant (si elle est à fermer) dans $_HYPR_CALLER_TO_CLOSE
# pour qu'on la ferme tout à la fin (sinon on se tuerait avant la restauration).
_HYPR_CALLER_TO_CLOSE=""
hypr_close_session_windows() {
  local f; f="$(_windows_snapshot_file)"
  _HYPR_CALLER_TO_CLOSE=""
  if ! hypr_available; then rm -f "$f"; return 0; fi
  if [[ ! -f "$f" ]]; then
    is_active && warn "pas de liste des fenêtres d'avant le mode — seules les fenêtres de la disposition sont fermées."
    return 1
  fi
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s fermerait toutes les fenêtres ouvertes pendant le mode\n' "$_c_dim" "$_c_reset"
    rm -f "$f"; return 0
  fi

  local clients caller addr cls n=0 left
  clients=$(hyprctl clients -j 2>/dev/null) || { rm -f "$f"; return 1; }
  caller=$(_caller_window "$clients")
  while IFS=$'\t' read -r addr cls; do
    [[ -n "$addr" ]] || continue
    grep -qxF "$addr" "$f" && continue                     # existait avant : on garde
    if [[ "$addr" == "$caller" ]]; then _HYPR_CALLER_TO_CLOSE="$addr"; continue; fi
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1 || true
    n=$((n+1))
  done < <(jq -r '.[] | "\(.address)\t\(.class)"' <<<"$clients")

  if (( n > 0 )); then
    sleep 0.5
    left=$(hyprctl clients -j 2>/dev/null | jq -r '.[].address' | grep -cvxF -f "$f" || true)
    [[ -n "$_HYPR_CALLER_TO_CLOSE" ]] && left=$((left-1))
    log "fenêtres du mode fermées : $n."
    (( left > 0 )) && warn "$left fenêtre(s) encore ouverte(s) (confirmation demandée par l'app ?)."
  else
    log "aucune autre fenêtre ouverte pendant le mode."
  fi
  rm -f "$f"
  return 0
}

# Ferme la fenêtre de l'appelant mise de côté (à appeler en DERNIER).
hypr_close_caller_window() {
  [[ -n "$_HYPR_CALLER_TO_CLOSE" ]] || return 0
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$_HYPR_CALLER_TO_CLOSE\" })" >/dev/null 2>&1 || true
}
