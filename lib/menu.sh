#!/usr/bin/env bash
# lib/menu.sh — intégration au lanceur d'applications (menu walker d'Omarchy).
#
# Deux comportements symétriques, pour que le menu reflète le mode :
#
#   MODE NORMAL  : les apps cyber (Burp, ZAP…) sont MASQUÉES — liste
#                  config/menu-apps.list.
#   MODE PENTEST : les apps cyber + nos lanceurs sont VISIBLES ; et, si
#                  menu_focus=on, toutes les AUTRES apps (jeux, chat, musique,
#                  bureautique…) sont masquées — on ne garde qu'un socle
#                  essentiel : config/menu-keep.list (terminal, fichiers,
#                  Firefox, réglages, apps omarchy…) + les outils cyber + nos
#                  lanceurs.
#
# Mécanisme 100 % standard freedesktop, entièrement réversible :
#   - nos lanceurs « pentest-*.desktop » sont LIÉS puis retirés ;
#   - une app installée dans un répertoire système est masquée par une copie
#     locale « ombre » (NoDisplay=true) qui l'occulte ; révélée en retirant
#     l'ombre ;
#   - une app dont l'entrée est déjà LOCALE (propre à l'utilisateur) est éditée
#     EN PLACE après SAUVEGARDE, puis restaurée depuis la sauvegarde.
#
# On ne modifie jamais un fichier sans l'avoir d'abord sauvegardé, et chacune de
# nos interventions porte un marqueur « X-ModePentest= » pour un retour arrière
# fiable même après un plantage. Dépend de lib/common.sh et lib/lab.sh.

# --- Emplacements ------------------------------------------------------------
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_DATA_DIRS:=/usr/local/share:/usr/share}"
MENU_APPS_DIR="$XDG_DATA_HOME/applications"            # nos écritures vont ici
MENU_BACKUP_DIR="$PENTEST_STATE_DIR/menu-backups"     # sauvegardes des entrées éditées

# Répertoires système surclassables (tests).
: "${PENTEST_MENU_SYSDIRS:=/usr/share/applications /usr/local/share/applications}"

# Marqueurs de nos interventions (clé = valeur, dans le groupe [Desktop Entry]).
MENU_MARK_CYBER="X-ModePentest=cyber-shadow"   # ombre : app cyber masquée (mode normal)
MENU_MARK_FOCUS_SHADOW="X-ModePentest=focus-shadow" # ombre : app masquée en focus (pentest)
MENU_MARK_FOCUS_LOCAL="X-ModePentest=focus-local"   # édition en place d'une entrée locale
MENU_MARK_ANY="X-ModePentest="                 # motif commun à toutes nos marques

# --- Réglages ----------------------------------------------------------------
menu_enabled() { [[ "$(cfg_get menu_integration on)" == "on" ]]; }   # intégration globale
menu_focus_on() { [[ "$(cfg_get menu_focus on)" == "on" ]]; }        # masquage du reste en pentest

# --- Fichiers de données (version utilisateur si présente) -------------------
menu_tpl_dir() {
  local u="$PENTEST_CONFIG_DIR/applications"
  [[ -d "$u" ]] && printf '%s' "$u" || printf '%s' "$ROOT_DIR/applications"
}
menu_apps_file() {
  local u="$PENTEST_CONFIG_DIR/menu-apps.list"
  [[ -f "$u" ]] && printf '%s' "$u" || printf '%s' "$ROOT_DIR/config/menu-apps.list"
}
menu_keep_file() {
  local u="$PENTEST_CONFIG_DIR/menu-keep.list"
  [[ -f "$u" ]] && printf '%s' "$u" || printf '%s' "$ROOT_DIR/config/menu-keep.list"
}

# Rafraîchit le cache des entrées (best-effort).
menu_refresh_db() {
  command -v update-desktop-database >/dev/null 2>&1 || return 0
  runq update-desktop-database "$MENU_APPS_DIR"
}

# --- Lecture des listes ------------------------------------------------------
# Itère sur les id (hors commentaires/vides) d'un fichier « un id par ligne ».
_menu_each_line() { # _menu_each_line <fichier> <callback>
  local f="$1" cb="$2" line id
  [[ -f "$f" ]] || return 0
  while IFS= read -r line; do
    id=${line%%#*}; id=${id//[[:space:]]/}
    [[ -n "$id" ]] && "$cb" "$id"
  done < "$f"
  return 0
}
_menu_each_app()  { _menu_each_line "$(menu_apps_file)" "$1"; }   # apps cyber

# Charge la liste blanche (socle à garder) dans le tableau MENU_KEEP.
MENU_KEEP=()
_menu_keep_add() { MENU_KEEP+=("$1"); }
_menu_load_keep() {
  MENU_KEEP=()
  _menu_each_line "$(menu_keep_file)" _menu_keep_add
}

# --- Répertoires d'applications (toutes sources XDG) -------------------------
_menu_app_dirs() {
  local seen=" " d
  printf '%s\n' "$MENU_APPS_DIR"; seen+=" $MENU_APPS_DIR "
  local IFS=:
  for d in $XDG_DATA_DIRS; do          # XDG_DATA_DIRS a une valeur par défaut (voir en-tête)
    [[ -n "$d" ]] || continue
    case "$seen" in *" $d/applications "*) : ;; *) printf '%s\n' "$d/applications"; seen+=" $d/applications ";; esac
  done
}

# Chemin EFFECTIF d'un id (le local l'emporte sur le système). Vide si absent.
_menu_effective_path() { # <id>
  local id="$1" d
  while IFS= read -r d; do
    [[ -f "$d/$id.desktop" ]] && { printf '%s' "$d/$id.desktop"; return 0; }
  done < <(_menu_app_dirs)
  printf ''
}
# Chemin SYSTÈME d'un id (ignore le local). Vide si l'app n'est pas installée.
_menu_sys_path() { # <id>
  local id="$1" d
  for d in $PENTEST_MENU_SYSDIRS; do
    [[ -f "$d/$id.desktop" ]] && { printf '%s' "$d/$id.desktop"; return 0; }
  done
  printf ''
}

# --- Fabrication / retrait des ombres ---------------------------------------
# Vrai si <path> est une de NOS interventions.
_menu_is_ours() { [[ -f "$1" ]] && grep -qF "$MENU_MARK_ANY" "$1"; }

# Écrit une copie masquée de <src> vers <dst> avec <marker>.
_menu_write_shadow() { # <src> <dst> <marker>
  local src="$1" dst="$2" marker="$3"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s ombre NoDisplay : %s\n' "$_c_dim" "$_c_reset" "$dst"; return 0
  fi
  mkdir -p "$(dirname "$dst")"
  awk -v m="$marker" '
    /^[[:space:]]*NoDisplay[[:space:]]*=/ { next }
    /^[[:space:]]*X-ModePentest[[:space:]]*=/ { next }
    { print }
    /^\[Desktop Entry\][[:space:]]*$/ { print "NoDisplay=true"; print m }
  ' "$src" > "$dst"
}

# Édite EN PLACE une entrée locale : sauvegarde puis NoDisplay+marqueur focus.
_menu_inplace_hide() { # <path> <id>
  local path="$1" id="$2"
  _menu_is_ours "$path" && return 0                 # déjà traité
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s masque (en place, sauvegardé) : %s\n' "$_c_dim" "$_c_reset" "$path"; return 0
  fi
  mkdir -p "$MENU_BACKUP_DIR"
  [[ -f "$MENU_BACKUP_DIR/$id.desktop" ]] || cp "$path" "$MENU_BACKUP_DIR/$id.desktop"
  local tmp="$path.mp.tmp"
  awk -v m="$MENU_MARK_FOCUS_LOCAL" '
    /^[[:space:]]*NoDisplay[[:space:]]*=/ { next }
    { print }
    /^\[Desktop Entry\][[:space:]]*$/ { print "NoDisplay=true"; print m }
  ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Restaure une entrée locale éditée en place (depuis la sauvegarde si possible).
_menu_inplace_restore() { # <path> <id>
  local path="$1" id="$2"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s restaure : %s\n' "$_c_dim" "$_c_reset" "$path"; return 0
  fi
  if [[ -f "$MENU_BACKUP_DIR/$id.desktop" ]]; then
    mv -f "$MENU_BACKUP_DIR/$id.desktop" "$path"
  else                                              # repli : retire nos lignes
    local tmp="$path.mp.tmp"
    awk '
      /^[[:space:]]*X-ModePentest[[:space:]]*=/ { next }
      /^[[:space:]]*NoDisplay[[:space:]]*=[[:space:]]*true/ { next }
      { print }
    ' "$path" > "$tmp" && mv "$tmp" "$path"
  fi
}

# --- Apps cyber : masquer (normal) / révéler (pentest) -----------------------
menu_hide_app() { # <id>  — crée l'ombre si l'app système est installée
  local id="$1" sys; local local_f="$MENU_APPS_DIR/$id.desktop"
  sys=$(_menu_sys_path "$id"); [[ -n "$sys" ]] || return 0
  if [[ -e "$local_f" ]] && ! _menu_is_ours "$local_f"; then
    warn "menu : $id.desktop déjà présent (perso) — laissé tel quel."; return 0
  fi
  _menu_write_shadow "$sys" "$local_f" "$MENU_MARK_CYBER" && log "menu : $id masqué."
}
menu_reveal_app() { # <id>  — retire notre ombre cyber
  local id="$1"; local local_f="$MENU_APPS_DIR/$id.desktop"
  [[ -f "$local_f" ]] && grep -qF "$MENU_MARK_CYBER" "$local_f" || return 0
  run rm -f "$local_f" && log "menu : $id révélé."
}

# --- Lanceurs pentest --------------------------------------------------------
menu_link_launchers() {
  local tpl f base; tpl=$(menu_tpl_dir); [[ -d "$tpl" ]] || return 0
  mkdir -p "$MENU_APPS_DIR"
  for f in "$tpl"/pentest-*.desktop; do
    [[ -e "$f" ]] || continue; base=$(basename "$f")
    run ln -snf "$f" "$MENU_APPS_DIR/$base"
  done
  return 0
}
menu_unlink_launchers() {
  local tpl f base dst; tpl=$(menu_tpl_dir); [[ -d "$tpl" ]] || return 0
  for f in "$tpl"/pentest-*.desktop; do
    [[ -e "$f" ]] || continue; base=$(basename "$f"); dst="$MENU_APPS_DIR/$base"
    [[ -L "$dst" ]] && run rm -f "$dst"
  done
  return 0
}

# --- Mode focus : masquer tout sauf le socle + cyber + nos lanceurs ----------
# Un id doit-il rester visible ? (liste blanche, apps cyber, nos lanceurs)
_menu_is_kept() { # <id>
  # NB : nom de variable distinct de 'id' — _menu_each_line déclare son propre
  # 'id' local, qui masquerait le nôtre dans la closure (portée dynamique).
  local _mik_id="$1" pat
  [[ "$_mik_id" == pentest-* ]] && return 0
  for pat in "${MENU_KEEP[@]}"; do
    # shellcheck disable=SC2053
    [[ "$_mik_id" == $pat ]] && return 0    # glob autorisé (ex. omarchy-*)
  done
  # Les apps cyber sont gérées à part (révélées) : ne pas les masquer ici.
  _MIK_CYBER=1
  _is_c() { [[ "$1" == "$_mik_id" ]] && _MIK_CYBER=0; }
  _menu_each_app _is_c
  [[ "$_MIK_CYBER" == 0 ]] && return 0
  return 1
}

# Masque une app au titre du focus (ombre si système, sinon édition locale).
_menu_focus_hide_one() { # <id>
  local id="$1" eff; local local_f="$MENU_APPS_DIR/$id.desktop"
  eff=$(_menu_effective_path "$id"); [[ -n "$eff" ]] || return 0
  _menu_is_ours "$eff" && return 0                         # déjà masquée par nous
  grep -qE '^[[:space:]]*(NoDisplay|Hidden)[[:space:]]*=[[:space:]]*true' "$eff" && return 0  # déjà cachée
  grep -qE '^[[:space:]]*Type[[:space:]]*=[[:space:]]*Application' "$eff" || return 0         # pas une app
  if [[ "$eff" == "$local_f" ]]; then
    _menu_inplace_hide "$eff" "$id"                        # entrée locale : en place + sauvegarde
  else
    _menu_write_shadow "$eff" "$local_f" "$MENU_MARK_FOCUS_SHADOW"  # système : ombre locale
  fi
}

# Parcourt toutes les apps et masque celles hors liste blanche.
menu_focus_hide_all() {
  _menu_load_keep
  local d f id base seen=" "
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*.desktop; do
      [[ -e "$f" ]] || continue
      base=$(basename "$f"); id=${base%.desktop}
      case "$seen" in *" $id "*) continue ;; esac
      seen+=" $id "
      _menu_is_kept "$id" && continue
      _menu_focus_hide_one "$id"
    done
  done < <(_menu_app_dirs)
  return 0
}

# Retire tous les masquages de focus (ombres focus + éditions locales).
menu_focus_unhide_all() {
  local f base id
  for f in "$MENU_APPS_DIR"/*.desktop; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f"); id=${base%.desktop}
    if grep -qF "$MENU_MARK_FOCUS_SHADOW" "$f" 2>/dev/null; then
      run rm -f "$f"
    elif grep -qF "$MENU_MARK_FOCUS_LOCAL" "$f" 2>/dev/null; then
      _menu_inplace_restore "$f" "$id"
    fi
  done
  return 0
}

# --- États -------------------------------------------------------------------
# MODE PENTEST : révèle le cyber, ajoute les lanceurs, masque le reste (focus).
menu_show() {
  menu_enabled || return 0
  _menu_each_app menu_reveal_app
  menu_link_launchers
  menu_focus_on && menu_focus_hide_all
  menu_refresh_db
  return 0
}
# MODE NORMAL : retire le focus, retire les lanceurs, masque le cyber.
menu_hide() {
  menu_enabled || return 0
  menu_focus_unhide_all
  menu_unlink_launchers
  _menu_each_app menu_hide_app
  menu_refresh_db
  return 0
}
# Réconcilie après installation d'outils (le mode décide de l'état cible).
menu_reconcile() { menu_enabled || return 0; if is_active; then menu_show; else menu_hide; fi; return 0; }

# Nettoyage total (désinstallation) : rétablit le menu d'origine.
menu_reveal_all() {
  menu_focus_unhide_all
  menu_unlink_launchers
  local f
  for f in "$MENU_APPS_DIR"/*.desktop; do
    [[ -e "$f" ]] || continue
    grep -qF "$MENU_MARK_CYBER" "$f" 2>/dev/null && run rm -f "$f"
  done
  menu_refresh_db
  return 0
}

# --- Diagnostic --------------------------------------------------------------
menu_status() {
  menu_enabled || { printf 'Intégration menu : désactivée (menu_integration = off)\n'; return 0; }
  printf 'Intégration menu : activée   | focus pentest : %s\n' "$(menu_focus_on && echo on || echo off)"
  printf 'Apps cyber gérées (installées → état) :\n'
  local any=0
  _ms() {
    local id="$1" sys lf="$MENU_APPS_DIR/$1.desktop" st
    sys=$(_menu_sys_path "$id"); [[ -n "$sys" ]] || return 0; any=1
    { [[ -f "$lf" ]] && grep -qF "$MENU_MARK_CYBER" "$lf"; } && st="masquée" || st="visible"
    printf '  - %-24s %s\n' "$id" "$st"
  }
  _menu_each_app _ms
  [[ "$any" == 1 ]] || printf '  (aucune installée pour l instant)\n'
  local n_fs n_fl
  n_fs=$(grep -lF "$MENU_MARK_FOCUS_SHADOW" "$MENU_APPS_DIR"/*.desktop 2>/dev/null | wc -l)
  n_fl=$(grep -lF "$MENU_MARK_FOCUS_LOCAL"  "$MENU_APPS_DIR"/*.desktop 2>/dev/null | wc -l)
  printf 'Focus : %s apps masquées (%s ombres, %s éditées en place)\n' "$((n_fs+n_fl))" "$n_fs" "$n_fl"
  local tpl f base dst found=0; tpl=$(menu_tpl_dir)
  printf 'Lanceurs pentest liés :\n'
  for f in "$tpl"/pentest-*.desktop; do
    [[ -e "$f" ]] || continue; base=$(basename "$f"); dst="$MENU_APPS_DIR/$base"
    [[ -L "$dst" ]] && { printf '  - %s\n' "$base"; found=1; }
  done
  [[ "$found" == 1 ]] || printf '  (aucun — mode inactif)\n'
}
