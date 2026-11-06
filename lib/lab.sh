#!/usr/bin/env bash
# lib/lab.sh — dossiers de lab, périmètre (scope) et journal.
# Données dans ~/pentest/<lab> avec permissions restrictives (700).
# Dépend de lib/common.sh.

PENTEST_LAB_ROOT=$(cfg_get "lab_root" "$HOME/pentest")
PENTEST_LAB_ROOT="${PENTEST_LAB_ROOT/#\~/$HOME}"   # développe un ~ en tête

lab_dir() { printf '%s/%s' "$PENTEST_LAB_ROOT" "$1"; }

# Répertoire de modèles : version utilisateur si présente, sinon celle du projet.
_lab_template_dir() {
  local u="$PENTEST_CONFIG_DIR/templates"
  if [[ -d "$u" ]]; then printf '%s' "$u"; else printf '%s' "$ROOT_DIR/templates"; fi
}

# Instancie un modèle en remplaçant {{LAB}} / {{DATE}}, seulement si absent.
_seed() { # _seed <modele> <destination> <lab>
  local tpl="$1" dst="$2" lab="$3"
  [[ -f "$dst" ]] && return 0
  [[ -f "$tpl" ]] || { : > "$dst"; return 0; }
  sed -e "s/{{LAB}}/$lab/g" -e "s/{{DATE}}/$(date +%F)/g" "$tpl" > "$dst"
}

# Crée (idempotent) l'arborescence d'un lab avec permissions restrictives.
lab_init() {
  local lab="$1" d; d=$(lab_dir "$lab")
  local tpl; tpl=$(_lab_template_dir)

  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s créerait %s (+ scope/notes/scans/loot/captures/report, 700)\n' "$_c_dim" "$_c_reset" "$d"
    return 0
  fi

  mkdir -p "$PENTEST_LAB_ROOT"; chmod 700 "$PENTEST_LAB_ROOT" 2>/dev/null || true
  mkdir -p "$d"/{scope,notes,scans,loot,captures,report}
  chmod -R 700 "$d" 2>/dev/null || true

  _seed "$tpl/scope.md"  "$d/scope/scope.md"   "$lab"
  _seed "$tpl/notes.md"  "$d/notes/notes.md"   "$lab"
  _seed "$tpl/report.md" "$d/report/report.md" "$lab"
  touch "$d/journal.log"; chmod 600 "$d/journal.log" 2>/dev/null || true
  log "dossier de lab prêt : $d"
}

lab_scope_file() { printf '%s/scope/scope.md' "$(lab_dir "$1")"; }

# Cibles autorisées : lignes utiles sous « ## Cibles autorisées » (hors
# commentaires HTML et titres), jusqu'au prochain « ## ».
lab_scope_targets() {
  local f; f=$(lab_scope_file "$1")
  [[ -f "$f" ]] || return 0
  awk '
    /^## Cibles autorisées/ { grab=1; next }
    /^## / { grab=0 }
    grab {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      if (line=="" || line ~ /^<!--/ || line ~ /^#/) next
      print line
    }
  ' "$f"
}

# Résumé court du scope pour status / rappel (cibles séparées par ", " ou mention vide).
lab_scope_summary() {
  local t; t=$(lab_scope_targets "$1" | paste -sd ', ' -)
  [[ -n "$t" ]] && printf '%s' "$t" || printf '(aucune cible renseignée — édite scope/scope.md)'
}

# Ajoute une cible sous « ## Cibles autorisées ».
lab_scope_add() {
  local lab="$1" entry="$2" f; f=$(lab_scope_file "$lab")
  [[ -f "$f" ]] || { err "scope introuvable pour '$lab'."; return 1; }
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s ajouterait la cible "%s" à %s\n' "$_c_dim" "$_c_reset" "$entry" "$f"; return 0
  fi
  # Insère la ligne juste après l'en-tête de section.
  awk -v e="$entry" '
    { print }
    /^## Cibles autorisées/ && !done { print e; done=1 }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  ok "cible ajoutée au scope de '$lab' : $entry"
}

# Journal horodaté (session, commandes manuelles).
lab_journal() {
  local lab="$1" msg="$2" f; f="$(lab_dir "$lab")/journal.log"
  [[ "$PENTEST_DRY_RUN" == "1" ]] && { printf '%s[dry-run]%s journal[%s] %s\n' "$_c_dim" "$_c_reset" "$lab" "$msg"; return 0; }
  mkdir -p "$(dirname "$f")"
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$msg" >> "$f"
}

# ---------------------------------------------------------------------------
# Labs existants : liste + sélecteur interactif (pour « pentest on » sans nom).
# ---------------------------------------------------------------------------

# Liste les labs, le plus récemment utilisé d'abord (date du journal, sinon du
# dossier). Sortie : nom<TAB>AAAA-MM-JJ<TAB>détails (room / cible si connues).
lab_list() {
  [[ -d "$PENTEST_LAB_ROOT" ]] || return 0
  local d name ts meta room ip extra
  for d in "$PENTEST_LAB_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    if [[ -f "$d/journal.log" ]]; then ts=$(stat -c %Y "$d/journal.log")
    else ts=$(stat -c %Y "$d"); fi
    room=""; ip=""; meta="$d/meta.env"
    if [[ -f "$meta" ]]; then
      room=$( (set +u; source "$meta" 2>/dev/null; printf '%s' "${ROOM:-}") )
      ip=$(   (set +u; source "$meta" 2>/dev/null; printf '%s' "${TARGET_IP:-}") )
    fi
    extra="${room:+room $room}${room:+${ip:+ · }}${ip:+cible $ip}"
    printf '%s\t%s\t%s\t%s\n' "$ts" "$name" "$(date -d "@$ts" +%F)" "$extra"
  done | sort -t$'\t' -k1,1nr | cut -f2-
  return 0
}

# Sélecteur : choisir un lab existant ou en créer un nouveau.
# Affiche le nom choisi sur stdout (vide = annulé). L'interface va sur le TTY.
LAB_PICK_NEW="+ Nouveau lab…"
lab_pick() {
  local labs choice name
  labs=$(lab_list)
  if command -v fzf >/dev/null 2>&1; then
    choice=$( { printf '%s\t\t\n' "$LAB_PICK_NEW"; [[ -n "$labs" ]] && printf '%s\n' "$labs"; } \
      | column -t -s $'\t' -o '   ' \
      | fzf --layout=reverse --height=~50% --border --prompt='lab > ' \
            --header 'Choisis un lab existant ou crée-en un · Entrée = valider · Échap = annuler' \
      || true)
    choice=${choice%%   *}            # garde la 1re colonne (le nom)
    choice=${choice%"${choice##*[![:space:]]}"}
  else
    local opts=("$LAB_PICK_NEW") l
    while IFS=$'\t' read -r l _; do [[ -n "$l" ]] && opts+=("$l"); done <<<"$labs"
    PS3="Numéro du lab : "
    select choice in "${opts[@]}"; do break; done </dev/tty >&2
  fi
  [[ -n "$choice" ]] || return 0
  if [[ "$choice" == "$LAB_PICK_NEW" ]]; then
    read -r -e -p "Nom du nouveau lab : " name </dev/tty >&2 || true
    printf '%s' "$name"
  else
    printf '%s' "$choice"
  fi
}
