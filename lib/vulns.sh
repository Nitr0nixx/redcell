#!/usr/bin/env bash
# lib/vulns.sh — analyse HORS-LIGNE des résultats de reco : les versions de
# services détectées (services-latest.tsv, produit par recon_ports via le XML
# nmap) sont comparées à une base de règles (config/vuln-rules.txt) pour
# POINTER des vulnérabilités connues (CVE + référence).
#
# Strictement informatif : des CANDIDATS À VÉRIFIER, jamais des vulnérabilités
# confirmées ; AUCUNE exploitation, aucune sonde supplémentaire (lecture seule
# des fichiers déjà produits). Dépend de lib/common.sh, lib/lab.sh, lib/recon.sh.

# Fichier de règles : version utilisateur si présente, sinon celle du dépôt.
vuln_rules_file() {
  local u="$PENTEST_CONFIG_DIR/vuln-rules.txt"
  if [[ -f "$u" ]]; then printf '%s' "$u"; else printf '%s' "$ROOT_DIR/config/vuln-rules.txt"; fi
}

# Dernier TSV de services du lab (services-latest.tsv, sinon le plus récent).
_vuln_services_file() { # <lab>
  local dir f; dir="$(_recon_scans_dir "$1")"
  if [[ -s "$dir/services-latest.tsv" ]]; then printf '%s' "$dir/services-latest.tsv"; return 0; fi
  f=$(ls -1t "$dir"/services-*.tsv 2>/dev/null | head -1 || true)
  [[ -n "$f" ]] && printf '%s' "$f"
  return 0
}

# Analyse les services du lab et écrit <scans>/vulns.md (+ affichage).
vuln_analyze() { # <lab>
  local lab="$1" dir out sf rf
  dir="$(_recon_scans_dir "$lab")"; out="$dir/vulns.md"
  sf=$(_vuln_services_file "$lab")
  if [[ -z "$sf" || ! -s "$sf" ]]; then
    warn "aucun service à analyser — lance d'abord : pentest recon <cible>"
    return 0
  fi
  rf=$(vuln_rules_file)
  [[ -f "$rf" ]] || { warn "base de règles introuvable : $rf"; return 0; }

  local port svc ver hay line r pat id sev title ref n=0
  local -a hits=()
  while IFS=$'\t' read -r port _ svc ver; do
    [[ -n "$port" ]] || continue
    hay="$svc $ver"
    while IFS= read -r line; do
      # Ignore lignes vides / commentaires (« # » en tête).
      [[ -z "${line// }" || "${line#\#}" != "$line" ]] && continue
      # 5 champs séparés par « | ». Le MOTIF (champ 1) peut lui-même contenir
      # des « | » (alternance regex) : on épluche les 4 derniers champs par la
      # DROITE, le reste est le motif.
      [[ "$line" == *"|"*"|"*"|"*"|"* ]] || continue
      ref=${line##*|};  r=${line%|*}
      title=${r##*|};   r=${r%|*}
      sev=${r##*|};     r=${r%|*}
      id=${r##*|};      pat=${r%|*}
      if printf '%s' "$hay" | grep -qiE -- "$pat" 2>/dev/null; then
        hits+=("- **[$sev] $id** — $title — port $port (\`$ver\`) — $ref")
        n=$((n+1))
      fi
    done < "$rf"
  done < "$sf"

  mkdir -p "$dir"
  {
    printf '_Analyse indicative **hors-ligne** : versions détectées comparées à une base de règles connues. '
    printf 'Ce sont des **candidats à vérifier manuellement**, pas des vulnérabilités confirmées ; '
    printf 'aucune exploitation n'"'"'est effectuée. Reste dans le périmètre autorisé._\n\n'
    if ((n)); then printf '%s\n' "${hits[@]}"
    else printf '_Aucune correspondance dans la base de règles (élargis `vuln-rules.txt`)._\n'; fi
  } > "$out"

  if ((n)); then
    ok "vulnérabilités candidates : $n (détail : $out)"
    printf '%s\n' "${hits[@]}"
  else
    log "aucune correspondance de vulnérabilité connue (base de règles)."
  fi
  lab_journal "$lab" "VULN analyse : $n candidat(s)"

  # Exploit-DB local (searchsploit) — optionnel, hors-ligne, sur le XML nmap.
  if [[ "$(cfg_get recon_searchsploit off)" == "on" ]]; then
    if command -v searchsploit >/dev/null 2>&1; then
      local xml; xml=$(ls -1t "$dir"/nmap-services-*.xml 2>/dev/null | head -1 || true)
      if [[ -n "$xml" ]]; then
        log "searchsploit --nmap (base Exploit-DB locale)…"
        searchsploit --nmap "$xml" > "$dir/searchsploit.txt" 2>/dev/null || true
        printf '\n_Exploit-DB (searchsploit) : voir `searchsploit.txt`._\n' >> "$out"
      fi
    else
      warn "recon_searchsploit=on mais searchsploit absent (pentest install searchsploit)."
    fi
  fi
}

# Affiche la dernière analyse (sans recalculer).
vuln_show() { # <lab>
  local f; f="$(_recon_scans_dir "$1")/vulns.md"
  if [[ -f "$f" ]]; then cat "$f"; else echo "aucune analyse — lance : pentest recon vulns"; fi
}
