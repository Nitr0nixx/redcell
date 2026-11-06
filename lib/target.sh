#!/usr/bin/env bash
# lib/target.sh — confort « machine cible » pour les labs (TryHackMe & co.) :
#   - métadonnées par lab (room, URL, cible) dans <lab>/meta.env ;
#   - ta propre IP de tunnel VPN (pour LHOST / reverse shells) ;
#   - enregistrement de la cible (+ /etc/hosts optionnel, bloc dédié) ;
#   - capture de flags ;
#   - génération d'un writeup Markdown (portfolio).
#
# Aucune action offensive : on prépare/consigne, on ne scanne ni n'attaque.
# Dépend de lib/common.sh, lib/lab.sh (lab_dir/scope/journal) et lib/net.sh
# (vpn_tun_ip, priv).

# --- Métadonnées par lab (fichier plat KEY=valeur) ---------------------------
_meta_file() { printf '%s/meta.env' "$(lab_dir "$1")"; }

meta_get() { # <lab> <clé>
  local f line; f=$(_meta_file "$1")
  [[ -f "$f" ]] || { printf ''; return 0; }
  line=$(grep -E "^$2=" "$f" 2>/dev/null | head -1 || true)
  printf '%s' "${line#*=}"
}

meta_set() { # <lab> <clé> <valeur>
  local f; f=$(_meta_file "$1")
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s meta %s=%s\n' "$_c_dim" "$_c_reset" "$2" "$3"; return 0
  fi
  mkdir -p "$(dirname "$f")"; touch "$f"
  grep -v -E "^$2=" "$f" > "$f.tmp" 2>/dev/null || true; mv "$f.tmp" "$f"
  [[ -n "$3" ]] && printf '%s=%s\n' "$2" "$3" >> "$f"
  return 0
}

_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

# --- Ton IP de tunnel (LHOST) ------------------------------------------------
# Affiche l'IP tun* et la copie dans le presse-papier (wl-copy si présent).
my_ip() {
  local i; i=$(vpn_tun_ip)
  [[ -n "$i" ]] || { err "pas d'IP de tunnel — VPN connecté ? ('pentest vpn connect')"; return 1; }
  printf '%s\n' "$i"
  if [[ "$PENTEST_DRY_RUN" != "1" ]] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$i" | wl-copy >/dev/null 2>&1 && log "IP copiée dans le presse-papier."
  fi
  return 0
}

# --- /etc/hosts (bloc dédié, jamais toucher le reste) ------------------------
HOSTS_BEGIN="# >>> mode-pentest >>>"
HOSTS_END="# <<< mode-pentest <<<"

hosts_remove() {   # retire notre bloc (idempotent, best-effort)
  grep -qF "$HOSTS_BEGIN" /etc/hosts 2>/dev/null || return 0
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s retirerait le bloc mode-pentest de /etc/hosts\n' "$_c_dim" "$_c_reset"; return 0
  fi
  local tmp; tmp=$(mktemp)
  sed "/$HOSTS_BEGIN/,/$HOSTS_END/d" /etc/hosts > "$tmp"
  priv cp "$tmp" /etc/hosts || warn "échec mise à jour /etc/hosts."
  rm -f "$tmp"; return 0
}

hosts_add() { # <ip> <hostname>
  local ip="$1" host="$2"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s /etc/hosts += %s %s\n' "$_c_dim" "$_c_reset" "$ip" "$host"; return 0
  fi
  local tmp; tmp=$(mktemp)
  { sed "/$HOSTS_BEGIN/,/$HOSTS_END/d" /etc/hosts
    printf '%s\n%s\t%s\n%s\n' "$HOSTS_BEGIN" "$ip" "$host" "$HOSTS_END"; } > "$tmp"
  priv cp "$tmp" /etc/hosts || { warn "échec mise à jour /etc/hosts."; rm -f "$tmp"; return 1; }
  rm -f "$tmp"; return 0
}

# --- Cible -------------------------------------------------------------------
target_set() { # <lab> <ip> [nom]
  local lab="$1" ip="$2"; shift 2; local name="${*:-}"
  _is_ipv4 "$ip" || { err "IP invalide : '$ip' (attendu : a.b.c.d)"; return 2; }
  meta_set "$lab" TARGET_IP "$ip"
  meta_set "$lab" TARGET_NAME "$name"
  lab_scope_add "$lab" "$ip" >/dev/null 2>&1 || true
  lab_journal "$lab" "TARGET: $ip${name:+ ($name)}"
  ok "cible enregistrée : $ip${name:+  →  $name}"

  # /etc/hosts : seulement si un nom est donné et manage_hosts=on, avec accord.
  if [[ -n "$name" && "$(cfg_get manage_hosts on)" == "on" ]]; then
    local host="$name"; [[ "$host" == *.* ]] || host="$name.thm"
    local go=1
    if [[ "$PENTEST_DRY_RUN" != "1" ]]; then
      if command -v gum >/dev/null 2>&1; then
        gum confirm "Ajouter « $ip $host » à /etc/hosts (sudo) ?" || go=0
      else
        read -r -p "Ajouter « $ip $host » à /etc/hosts (sudo) ? [o/N] " a
        [[ "$a" =~ ^[oOyY]$ ]] || go=0
      fi
    fi
    if [[ "$go" == 1 ]] && hosts_add "$ip" "$host"; then
      meta_set "$lab" TARGET_HOST "$host"
      ok "ajouté à /etc/hosts : $host  (retiré à 'pentest off')"
    fi
  fi
  declare -F bar_refresh >/dev/null 2>&1 && bar_refresh || true
  browser_scope_changed "$lab"
  return 0
}

target_show() { # <lab>
  local lab="$1" ip name host; ip=$(meta_get "$lab" TARGET_IP)
  name=$(meta_get "$lab" TARGET_NAME); host=$(meta_get "$lab" TARGET_HOST)
  if [[ -z "$ip" ]]; then
    echo "aucune cible définie. Usage : pentest target <ip> [nom]"; return 0
  fi
  printf 'Cible : %s%s%s\n' "$ip" "${name:+  ($name)}" "${host:+  [/etc/hosts: $host]}"
}

target_ip() { meta_get "$1" TARGET_IP; }   # pour la barre / status

# --- Flags -------------------------------------------------------------------
flag_add() { # <lab> <valeur> [libellé…]
  local lab="$1" val="$2"; shift 2 || true; local label="${*:-flag}"
  [[ -n "$val" ]] || { err "usage : pentest flag <valeur> [libellé]"; return 2; }
  local f; f="$(lab_dir "$lab")/flags.md"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s flag -> %s\n' "$_c_dim" "$_c_reset" "$f"
  else
    mkdir -p "$(dirname "$f")"
    [[ -f "$f" ]] || printf '# Flags — %s\n\n' "$lab" > "$f"
    printf -- '- [%s] **%s** : `%s`\n' "$(date '+%F %T')" "$label" "$val" >> "$f"
  fi
  lab_journal "$lab" "FLAG ($label): $val"
  ok "flag enregistré ($label)."
}

# --- Room (métadonnées pour le writeup) --------------------------------------
room_set() { # <lab> <nom> [url]
  local lab="$1" name="$2"; shift 2 || true; local url="${*:-}"
  [[ -n "$name" ]] || { err "usage : pentest room <nom> [url]"; return 2; }
  meta_set "$lab" ROOM "$name"
  [[ -n "$url" ]] && meta_set "$lab" ROOM_URL "$url"
  lab_journal "$lab" "ROOM: $name${url:+ ($url)}"
  ok "room enregistrée : $name${url:+  ($url)}"
}

# --- Writeup (portfolio) -----------------------------------------------------
# Compile scope + cible + flags + notes + journal en un Markdown régénérable.
report_build() { # <lab>
  local lab="$1" dir out; dir=$(lab_dir "$lab"); out="$dir/report/writeup.md"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s générerait le writeup : %s\n' "$_c_dim" "$_c_reset" "$out"; return 0
  fi
  local room url ip tname thost
  room=$(meta_get "$lab" ROOM); url=$(meta_get "$lab" ROOM_URL)
  ip=$(meta_get "$lab" TARGET_IP); tname=$(meta_get "$lab" TARGET_NAME); thost=$(meta_get "$lab" TARGET_HOST)
  mkdir -p "$(dirname "$out")"
  {
    printf '# Writeup — %s\n\n' "${room:-$lab}"
    printf '_Généré le %s par mode-pentest — régénéré à chaque `pentest report`._\n\n' "$(date '+%F %T')"
    printf '## Contexte\n\n'
    printf -- '- **Room** : %s\n' "${room:-$lab}"
    [[ -n "$url" ]]   && printf -- '- **URL** : %s\n' "$url"
    [[ -n "$ip" ]]    && printf -- '- **Cible** : %s%s%s\n' "$ip" "${tname:+ ($tname)}" "${thost:+ — $thost}"
    printf -- '- **Dossier** : `%s`\n\n' "$dir"
    printf '## Périmètre autorisé\n\n'
    if [[ -f "$dir/scope/scope.md" ]]; then sed 's/^/> /' "$dir/scope/scope.md"; else echo '_non défini_'; fi
    printf '\n## Reconnaissance\n\n'
    if [[ -f "$dir/scans/summary.md" ]]; then
      sed '1d' "$dir/scans/summary.md"   # retire le titre « # Reconnaissance — <lab> »
    else
      echo '_aucune reconnaissance enregistrée (`pentest recon <cible>`)_'
    fi
    printf '\n## Flags\n\n'
    if [[ -f "$dir/flags.md" ]] && grep -qE '^- ' "$dir/flags.md"; then grep -E '^- ' "$dir/flags.md"; else echo '_aucun_'; fi
    printf '\n## Notes\n\n'
    if [[ -f "$dir/notes/notes.md" ]]; then cat "$dir/notes/notes.md"; else echo '_aucune_'; fi
    printf '\n## Journal de session\n\n```\n'
    [[ -f "$dir/journal.log" ]] && cat "$dir/journal.log" || echo '(vide)'
    printf '```\n'
  } > "$out"
  ok "writeup généré : $out"
}
