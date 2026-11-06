#!/usr/bin/env bash
# lib/recon.sh — reconnaissance de base, STRICTEMENT limitée au périmètre du lab.
#
# Philosophie : cet outil est fait pour des labs/missions AUTORISÉS (TryHackMe,
# HTB, missions avec mandat écrit). Avant toute sonde réseau, la cible doit :
#   1. figurer dans le périmètre du lab actif (scope/scope.md ou cible définie) ;
#   2. passer par le tunnel VPN (une IP tun* doit exister) ;
#   3. être confirmée par toi (scan actif = on touche la cible).
# Si l'un de ces points manque, on refuse. C'est le garde-fou légal du projet.
#
# Enchaînement (recon « enum + découverte web légère ») :
#   liveness (ping) → nmap ports → nmap services/versions sur ports ouverts →
#   suivi par service : HTTP (whatweb + découverte de contenu légère),
#   DNS (dnsrecon), SMB (smbclient -L).
# AUCUN brute-force, AUCun exploit, AUCUN scan de vuln lourd.
#
# Dépend de lib/common.sh (cfg_get, logs, dry-run), lib/lab.sh (lab_dir,
# lab_scope_targets, lab_journal), lib/net.sh (vpn_tun_ip), lib/target.sh (meta_get).

# --- Scope : la cible est-elle autorisée ? -----------------------------------

# Teste si l'IPv4 $1 appartient au CIDR $2 (a.b.c.d/n). Renvoie 0 si oui.
_recon_ip_in_cidr() { # <ip> <cidr>
  local ip="$1" cidr="$2" net mask a b
  [[ "$cidr" == */* ]] || return 1
  net="${cidr%/*}"; mask="${cidr#*/}"
  [[ "$mask" =~ ^[0-9]+$ ]] && (( mask >= 0 && mask <= 32 )) || return 1
  _recon_is_ipv4 "$ip" && _recon_is_ipv4 "$net" || return 1
  a=$(_recon_ip2int "$ip"); b=$(_recon_ip2int "$net")
  local bits=$(( mask == 0 ? 0 : (0xFFFFFFFF << (32 - mask)) & 0xFFFFFFFF ))
  (( (a & bits) == (b & bits) ))
}

_recon_is_ipv4() { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }

_recon_ip2int() { # <a.b.c.d>
  local IFS=.; read -r o1 o2 o3 o4 <<<"$1"
  printf '%d' "$(( (o1<<24) + (o2<<16) + (o3<<8) + o4 ))"
}

# Vrai (0) si <target> est couvert par le périmètre du lab <lab>.
# Autorisé si : égal à une entrée du scope ; dans un CIDR du scope ;
# égal à la cible définie (TARGET_IP / TARGET_NAME / TARGET_HOST).
recon_in_scope() { # <lab> <target>
  local lab="$1" target="$2" entry
  [[ -n "$target" ]] || return 1

  # Cible définie dans les métadonnées du lab.
  local tip tname thost
  tip=$(meta_get "$lab" TARGET_IP   2>/dev/null || true)
  tname=$(meta_get "$lab" TARGET_NAME 2>/dev/null || true)
  thost=$(meta_get "$lab" TARGET_HOST 2>/dev/null || true)
  [[ -n "$tip"   && "$target" == "$tip"   ]] && return 0
  [[ -n "$tname" && "$target" == "$tname" ]] && return 0
  [[ -n "$thost" && "$target" == "$thost" ]] && return 0

  # Entrées explicites du scope (IP, hostname, ou CIDR).
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    # On ne garde que le 1er champ (au cas où la ligne ait un commentaire).
    entry=${entry%%[[:space:]]*}
    [[ "$target" == "$entry" ]] && return 0
    if [[ "$entry" == */* ]] && _recon_is_ipv4 "$target"; then
      _recon_ip_in_cidr "$target" "$entry" && return 0
    fi
  done < <(lab_scope_targets "$lab")

  return 1
}

# --- Échéance du périmètre (clause « until ») ---------------------------------
# Une entrée de scope peut porter une échéance : « 10.10.0.0/16 until 2026-11-07 »
# (ou « …T18:00 »). Passé ce moment, elle ne couvre plus rien.

# Horodatage après 'until' dans une ligne de scope (vide si aucun).
_scope_entry_expiry() { # <ligne>
  local line="$1"
  [[ "$line" =~ [[:space:]]until[[:space:]]+([^[:space:]#]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}

# Vrai (0) si <target> est couvert par AU MOINS une entrée encore valide (non
# expirée), ou par la cible définie du lab (jamais d'échéance). Une échéance
# illisible est considérée valide (fail-open ; signalée par ailleurs).
scope_valid_cover() { # <lab> <target>
  local lab="$1" target="$2" entry spec exp now exp_epoch match
  now=$(date +%s)
  local tip tname thost
  tip=$(meta_get "$lab" TARGET_IP   2>/dev/null || true)
  tname=$(meta_get "$lab" TARGET_NAME 2>/dev/null || true)
  thost=$(meta_get "$lab" TARGET_HOST 2>/dev/null || true)
  [[ -n "$tip"   && "$target" == "$tip"   ]] && return 0
  [[ -n "$tname" && "$target" == "$tname" ]] && return 0
  [[ -n "$thost" && "$target" == "$thost" ]] && return 0
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    spec=${entry%%[[:space:]]*}
    match=0
    [[ "$target" == "$spec" ]] && match=1
    if [[ $match -eq 0 && "$spec" == */* ]] && _recon_is_ipv4 "$target"; then
      _recon_ip_in_cidr "$target" "$spec" && match=1
    fi
    [[ $match -eq 1 ]] || continue
    exp=$(_scope_entry_expiry "$entry")
    [[ -z "$exp" ]] && return 0                       # pas d'échéance = valide
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    [[ "$exp_epoch" -eq 0 || "$now" -lt "$exp_epoch" ]] && return 0
  done < <(lab_scope_targets "$lab")
  return 1
}

# Lignes de scope dont l'échéance est passée (pour avertir à l'activation).
scope_expired_entries() { # <lab>
  local lab="$1" entry exp now exp_epoch; now=$(date +%s)
  while IFS= read -r entry; do
    exp=$(_scope_entry_expiry "$entry"); [[ -n "$exp" ]] || continue
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    [[ "$exp_epoch" -gt 0 && "$now" -ge "$exp_epoch" ]] && printf '%s\n' "$entry"
  done < <(lab_scope_targets "$lab")
}

# --- Journal d'audit des sondes actives ---------------------------------------
# Trace append-only : chaque sonde émise (commande + cible + horodatage). Le lab
# et la cible courants sont posés par recon_guard juste avant d'autoriser.
_recon_audit() { # <cmd...>
  [[ "$PENTEST_DRY_RUN" == "1" ]] && return 0
  [[ -n "${RECON_AUDIT_LAB:-}" ]] || return 0
  local f; f="$(lab_dir "$RECON_AUDIT_LAB")/audit.log"
  mkdir -p "$(dirname "$f")"
  printf '%s\tcible=%s\t%s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "${RECON_AUDIT_TARGET:-?}" "$*" >> "$f"
}

# Affiche le journal d'audit du lab.
recon_audit_show() { # <lab>
  local f; f="$(lab_dir "$1")/audit.log"
  if [[ -s "$f" ]]; then cat "$f"; else echo "aucune sonde enregistrée pour « $1 » (audit.log vide)."; fi
}

# --- Préconditions ------------------------------------------------------------

# Résout la cible : argument explicite, sinon TARGET_IP du lab.
recon_resolve_target() { # <lab> [target]
  local lab="$1" t="${2:-}"
  [[ -n "$t" ]] && { printf '%s' "$t"; return 0; }
  meta_get "$lab" TARGET_IP
}

# Vérifie VPN + scope + confirmation. Renvoie 0 si on peut sonder <target>.
recon_guard() { # <lab> <target> [--yes]
  local lab="$1" target="$2" yes="${3:-}"

  if [[ -z "$target" ]]; then
    err "aucune cible. Usage : pentest recon <ip|host>  (ou définis-la : pentest target <ip>)"
    return 2
  fi

  # 1. Scope — le garde-fou. Jamais de sonde hors périmètre.
  if ! recon_in_scope "$lab" "$target"; then
    err "REFUS : « $target » n'est pas dans le périmètre autorisé du lab « $lab »."
    warn "Cibles autorisées : $(lab_scope_summary "$lab")"
    warn "Ajoute-la si tu y es autorisé : pentest scope add $target   (ou : pentest target $target)"
    return 3
  fi

  # 1bis. Échéance — le périmètre couvre la cible, mais toutes les entrées qui
  # la couvrent ont expiré (clause « until »). On refuse, distinctement.
  if ! scope_valid_cover "$lab" "$target"; then
    err "REFUS : le périmètre couvrant « $target » a EXPIRÉ (clause 'until' dans scope/scope.md)."
    warn "Prolonge l'échéance (pentest scope add $target until <date>) ou retire la clause si tu y es toujours autorisé."
    return 3
  fi

  # 2. VPN — la reco doit passer par le tunnel du lab, pas ton IP réelle.
  if [[ "$(cfg_get recon_require_vpn on)" == "on" && "$PENTEST_DRY_RUN" != "1" ]]; then
    if [[ -z "$(vpn_tun_ip)" ]]; then
      err "REFUS : pas de tunnel VPN actif. Connecte-toi d'abord : pentest vpn connect"
      warn "(désactivable pour un lab local via recon_require_vpn=off dans config.toml)"
      return 4
    fi
  fi

  # 3. Confirmation — un scan actif touche la cible.
  if [[ "$(cfg_get recon_confirm on)" == "on" && "$PENTEST_DRY_RUN" != "1" && "$yes" != "--yes" ]]; then
    local go=1
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Lancer une reconnaissance ACTIVE sur « $target » (dans le scope) ?" || go=0
    else
      read -r -p "Lancer une reconnaissance ACTIVE sur « $target » ? [o/N] " a
      [[ "$a" =~ ^[oOyY]$ ]] || go=0
    fi
    [[ "$go" == 1 ]] || { warn "annulé."; return 1; }
  fi

  # Autorisé : on arme le journal d'audit (lab + cible) pour les sondes à venir.
  RECON_AUDIT_LAB="$lab"; RECON_AUDIT_TARGET="$target"
  return 0
}

# Vérifie la présence d'un outil ; sinon explique comment l'installer (sans l'installer).
recon_need() { # <binaire> <paquet-hint>
  command -v "$1" >/dev/null 2>&1 && return 0
  warn "outil manquant : $1 — installe-le avec : pentest install ${2:-$1}"
  return 1
}

# --- Exécution + archivage ----------------------------------------------------

_recon_scans_dir() { printf '%s/scans' "$(lab_dir "$1")"; }
_recon_ts() { date +'%Y%m%d-%H%M%S'; }

# Exécute une commande de scan : en dry-run l'affiche ; sinon la lance en
# enregistrant la sortie dans <outfile> (et à l'écran). Renvoie le code de la cmd.
_recon_run() { # <outfile> <cmd...>
  local out="$1"; shift
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s %s  > %s\n' "$_c_dim" "$_c_reset" "$*" "$out"
    return 0
  fi
  mkdir -p "$(dirname "$out")"
  _recon_audit "$@"
  log "→ $*"
  # tee pour garder la trace ET voir défiler ; on capture le code de la cmd.
  "$@" 2>&1 | tee "$out"
  return "${PIPESTATUS[0]}"
}

# Ajoute une ligne au résumé Markdown du lab (repris par « pentest report »).
_recon_summary() { # <lab> <ligne markdown>
  local lab="$1" line="$2" f; f="$(_recon_scans_dir "$lab")/summary.md"
  [[ "$PENTEST_DRY_RUN" == "1" ]] && return 0
  mkdir -p "$(dirname "$f")"
  [[ -f "$f" ]] || printf '# Reconnaissance — %s\n\n' "$lab" > "$f"
  printf -- '%s\n' "$line" >> "$f"
}

# Parse un XML nmap (-oX) en lignes « port<TAB>proto<TAB>service<TAB>version »,
# ports 'open' seulement. Source structurée robuste (vs grep sur le texte).
# Utilise python3 (stdlib) ; renvoie 1 s'il est absent ou si le XML est illisible.
_recon_nmap_xml_tsv() { # <fichier.xml>  → TSV sur stdout
  command -v python3 >/dev/null 2>&1 || return 1
  [[ -f "$1" ]] || return 1
  python3 -I - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(1)
rows = 0
for host in root.findall('host'):
    for port in host.findall('./ports/port'):
        st = port.find('state')
        if st is None or st.get('state') != 'open':
            continue
        svc = port.find('service')
        name = (svc.get('name') if svc is not None else '') or '?'
        ver = ''
        if svc is not None:
            ver = ' '.join(x for x in (svc.get('product'), svc.get('version'),
                                       svc.get('extrainfo')) if x)
        print('\t'.join((port.get('portid', '?'), port.get('protocol', ''),
                         name, ver.strip() or '-')))
        rows += 1
sys.exit(0 if rows else 1)
PY
}

# --- Étapes de reconnaissance -------------------------------------------------

# Liveness : un seul ping (déjà la philosophie de net.sh).
recon_liveness() { # <lab> <target>
  local lab="$1" t="$2"
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s ping -c1 -W2 %s\n' "$_c_dim" "$_c_reset" "$t"; return 0
  fi
  _recon_audit "ping -c1 -W2 $t"
  if ping -c1 -W2 "$t" >/dev/null 2>&1; then
    ok "hôte joignable (ICMP) : $t"
  else
    warn "pas de réponse ICMP (fréquent : la cible filtre le ping ; on scanne quand même)."
  fi
}

# Ports : nmap connect-scan (pas de root requis), puis services/versions.
# Écrit un .txt lisible + un .gnmap, et renvoie la liste des ports ouverts (CSV).
recon_ports() { # <lab> <target>  → imprime la liste des ports ouverts
  local lab="$1" t="$2" dir ts timing topn
  dir=$(_recon_scans_dir "$lab"); ts=$(_recon_ts)
  timing=$(cfg_get recon_timing 3)
  topn=$(cfg_get recon_top_ports 1000)
  recon_need nmap nmap || return 0

  local base="$dir/nmap-ports-$ts"
  _recon_run "$base.txt" \
    nmap -sT -n -Pn -T"$timing" --top-ports "$topn" -oG "$base.gnmap" "$t" >&2 || true

  # Ports ouverts depuis la sortie grepable (ou le .txt en dry-run : rien).
  local ports=""
  if [[ "$PENTEST_DRY_RUN" != "1" && -f "$base.gnmap" ]]; then
    ports=$(grep -hoE '[0-9]+/open' "$base.gnmap" 2>/dev/null | cut -d/ -f1 | sort -un | paste -sd, - || true)
  fi

  if [[ -n "$ports" ]]; then
    ok "ports ouverts : $ports" >&2
    _recon_summary "$lab" "## $ts — $t"
    _recon_summary "$lab" "- Ports ouverts : \`$ports\`"
    # Services/versions sur les ports trouvés (scripts par défaut, pas de vuln).
    # XML (-oX) en plus du texte : sert à produire un tableau structuré.
    local svc="$dir/nmap-services-$ts"
    _recon_run "$svc.txt" nmap -sV -sC -n -Pn -T"$timing" -oX "$svc.xml" -p "$ports" "$t" >&2 || true
    # Tableau structuré depuis le XML (si python3 présent) ; sinon simple renvoi.
    local tsv; tsv=$(_recon_nmap_xml_tsv "$svc.xml" 2>/dev/null || true)
    if [[ -n "$tsv" ]]; then
      printf '%s\n' "$tsv" > "$dir/services-latest.tsv"
      cp -f "$dir/services-latest.tsv" "$dir/services-$ts.tsv" 2>/dev/null || true
      _recon_summary "$lab" ""
      _recon_summary "$lab" "| Port | Proto | Service | Version |"
      _recon_summary "$lab" "|------|-------|---------|---------|"
      local pn pr sv vr
      while IFS=$'\t' read -r pn pr sv vr; do
        [[ -n "$pn" ]] || continue
        _recon_summary "$lab" "| $pn | $pr | $sv | $vr |"
      done <<<"$tsv"
      _recon_summary "$lab" ""
      _recon_summary "$lab" "- Détail brut : \`$(basename "$svc.txt")\`"
    else
      : > "$dir/services-latest.tsv"   # pas de table : évite une reco périmée
      _recon_summary "$lab" "- Détail services : \`$(basename "$svc.txt")\`"
    fi
  elif [[ "$PENTEST_DRY_RUN" != "1" ]]; then
    warn "aucun port ouvert détecté dans le top-$topn." >&2
    _recon_summary "$lab" "## $ts — $t"
    _recon_summary "$lab" "- Aucun port ouvert dans le top-$topn."
  fi

  lab_journal "$lab" "RECON ports $t : ${ports:-aucun}"
  printf '%s' "$ports"
}

# Web : empreinte (whatweb / en-têtes) + découverte de contenu LÉGÈRE.
recon_web() { # <lab> <target> <port>
  local lab="$1" t="$2" port="$3" dir ts scheme url
  dir=$(_recon_scans_dir "$lab"); ts=$(_recon_ts)
  scheme=http; [[ "$port" == "443" || "$port" == "8443" ]] && scheme=https
  url="$scheme://$t:$port/"

  log "web : $url"
  # Empreinte : whatweb si présent, sinon en-têtes via curl.
  if command -v whatweb >/dev/null 2>&1; then
    _recon_run "$dir/whatweb-$port-$ts.txt" whatweb -a 1 "$url" || true
  elif command -v curl >/dev/null 2>&1; then
    _recon_run "$dir/headers-$port-$ts.txt" curl -sS -I -m 10 "$url" || true
  else
    warn "ni whatweb ni curl — empreinte web ignorée."
  fi

  # Découverte de contenu légère (optionnelle, petite wordlist, débit limité).
  if [[ "$(cfg_get recon_web_discovery on)" == "on" ]]; then
    local wl; wl=$(cfg_get recon_web_wordlist "$ROOT_DIR/config/recon-web-small.txt")
    [[ -f "$wl" ]] || wl="$ROOT_DIR/config/recon-web-small.txt"
    if command -v gobuster >/dev/null 2>&1 && [[ -f "$wl" ]]; then
      _recon_run "$dir/gobuster-$port-$ts.txt" \
        gobuster dir -q -u "$url" -w "$wl" -t 10 --timeout 10s -k || true
      _recon_summary "$lab" "- Web $url : découverte → \`gobuster-$port-$ts.txt\`"
    elif command -v ffuf >/dev/null 2>&1 && [[ -f "$wl" ]]; then
      _recon_run "$dir/ffuf-$port-$ts.txt" \
        ffuf -s -u "${url}FUZZ" -w "$wl" -rate 20 -t 10 || true
      _recon_summary "$lab" "- Web $url : découverte → \`ffuf-$port-$ts.txt\`"
    else
      warn "découverte web : ni gobuster ni ffuf (ou wordlist absente) — ignorée."
      warn "  installe : pentest install gobuster"
    fi
  fi
  _recon_summary "$lab" "- Web détecté sur le port $port ($url)"
  lab_journal "$lab" "RECON web $url"
}

# DNS : reco légère si un service DNS est exposé.
recon_dns() { # <lab> <target>
  local lab="$1" t="$2" dir ts; dir=$(_recon_scans_dir "$lab"); ts=$(_recon_ts)
  if command -v dnsrecon >/dev/null 2>&1; then
    _recon_run "$dir/dnsrecon-$ts.txt" dnsrecon -n "$t" -d "$t" -t std || true
  else
    warn "dnsrecon absent — reco DNS ignorée (pentest install dnsrecon)."
  fi
  lab_journal "$lab" "RECON dns $t"
}

# SMB : listing des partages (lecture seule, anonyme) si 139/445 ouverts.
recon_smb() { # <lab> <target>
  local lab="$1" t="$2" dir ts; dir=$(_recon_scans_dir "$lab"); ts=$(_recon_ts)
  if command -v smbclient >/dev/null 2>&1; then
    _recon_run "$dir/smb-$ts.txt" smbclient -L "//$t/" -N || true
  else
    warn "smbclient absent — énumération SMB ignorée (pentest install smbclient)."
  fi
  lab_journal "$lab" "RECON smb $t"
}

# --- Orchestration ------------------------------------------------------------

# Chaîne complète : liveness → ports → suivi par service détecté.
recon_full() { # <lab> <target> [--yes]
  local lab="$1" t="$2" yes="${3:-}"
  recon_guard "$lab" "$t" "$yes" || return $?

  ok "reconnaissance de « $t » (lab : $lab) — scope vérifié."
  recon_liveness "$lab" "$t"

  local ports; ports=$(recon_ports "$lab" "$t")

  # Suivi déclenché par les services réellement détectés. Si le tableau
  # structuré existe (nmap -oX + python3), on route par NOM de service — plus
  # fiable : un HTTP sur un port exotique est suivi, un 80 non-HTTP ne l'est pas.
  # Sinon, repli sur le numéro de port (comportement historique).
  local svcfile="$(_recon_scans_dir "$lab")/services-latest.tsv"
  if [[ -s "$svcfile" ]]; then
    local pn pr sv vr
    while IFS=$'\t' read -r pn pr sv vr; do
      [[ -n "$pn" ]] || continue
      case "$sv" in
        http|http-alt|http-proxy|https|https-alt|ssl/http|ssl|ssl/https|sip) recon_web "$lab" "$t" "$pn" ;;
        domain)                   recon_dns "$lab" "$t" ;;
        microsoft-ds|netbios-ssn) recon_smb "$lab" "$t" ;;
      esac
    done < "$svcfile"
  elif [[ -n "$ports" ]]; then
    local IFS=,; local p
    for p in $ports; do
      case "$p" in
        80|81|443|591|8000|8008|8080|8443|8888) recon_web "$lab" "$t" "$p" ;;
        53)       recon_dns "$lab" "$t" ;;
        139|445)  recon_smb "$lab" "$t" ;;
      esac
    done
  fi

  ok "reco terminée. Résumé : $(_recon_scans_dir "$lab")/summary.md"
  ok "voir : pentest recon show   |   writeup : pentest report"
}

# Affiche le résumé de reco du lab.
recon_show() { # <lab>
  local f; f="$(_recon_scans_dir "$1")/summary.md"
  if [[ -f "$f" ]]; then cat "$f"; else echo "aucune reco enregistrée pour « $1 » (pentest recon <cible>)."; fi
}
