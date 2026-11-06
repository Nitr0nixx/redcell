#!/usr/bin/env bash
# tests/test_vulns.sh — analyse hors-ligne des vulnérabilités (lib/vulns.sh).
# Bac à sable : on fabrique un services-latest.tsv et on vérifie le pointage de
# CVE connus. Lecture seule, AUCUNE sonde, aucun réseau.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
LAB=thm
mkdir -p "$HOME/pentest/$LAB/scans" "$HOME/pentest/$LAB/report" \
         "$XDG_CONFIG_HOME/mode-pentest" "$XDG_STATE_HOME/mode-pentest"
printf 'lab_root = "~/pentest"\nmenu_integration = "off"\nmanage_hosts = "off"\n' \
  > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
printf '%s\n' "$LAB" > "$XDG_STATE_HOME/mode-pentest/active"
LABDIR="$HOME/pentest/$LAB"
# Services détectés (format produit par recon_ports via le XML nmap) :
# vulnérables (vsftpd, OpenSSH<7.7, Apache 2.4.49, Exim, Samba) + sains.
cat > "$LABDIR/scans/services-latest.tsv" <<'TSV'
21	tcp	ftp	vsftpd 2.3.4
22	tcp	ssh	OpenSSH 7.6p1 Ubuntu
80	tcp	http	Apache httpd 2.4.49
25	tcp	smtp	Exim smtpd 4.89
445	tcp	netbios-ssn	Samba smbd 4.5.9
8080	tcp	http	Apache httpd 2.4.58
3306	tcp	mysql	MySQL 8.0.32
TSV

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Analyse de vulnérabilités (hors-ligne) =="

O=$("$PENTEST" recon vulns 2>&1)
V="$LABDIR/scans/vulns.md"

echo "[1] CVE connus pointés"
check "vulns.md généré"                 test -f "$V"
check "vsftpd 2.3.4 -> CVE-2011-2523"   grep -q "CVE-2011-2523" "$V"
check "OpenSSH 7.6 -> CVE-2018-15473"   grep -q "CVE-2018-15473" "$V"
check "Apache 2.4.49 -> CVE-2021-41773" grep -q "CVE-2021-41773" "$V"
check "Exim 4.89 -> CVE-2019-10149"     grep -q "CVE-2019-10149" "$V"
check "Samba 4.5.9 -> CVE-2017-7494"    grep -q "CVE-2017-7494" "$V"
check "résumé à l'écran (compte)"       grep -q "vulnérabilités candidates" <<<"$O"

echo "[2] pas de faux positif"
check "Apache 2.4.58 NON signalé"       bash -c '! grep -q "2.4.58" "'"$V"'"'
check "MySQL 8.0.32 non signalé"        bash -c '! grep -qi "mysql" "'"$V"'"'

echo "[3] cadrage (informatif, pas d'exploitation)"
check "mention 'candidats à vérifier'"  grep -qi "candidats à vérifier" "$V"
check "mention 'aucune exploitation'"   grep -qi "aucune exploitation" "$V"
check "référence NVD/CVE présente"      grep -q "nvd.nist.gov" "$V"

echo "[4] reprise dans le writeup"
"$PENTEST" report >/dev/null 2>&1
check "section Vulnérabilités dans le writeup" grep -q "## Vulnérabilités" "$LABDIR/report/writeup.md"
check "CVE repris dans le writeup"      grep -q "CVE-2011-2523" "$LABDIR/report/writeup.md"

echo "[5] aucun service analysé -> message clair, pas d'échec"
rm -f "$LABDIR/scans/services-latest.tsv"
O=$("$PENTEST" recon vulns 2>&1)
check "signale l'absence de services"   grep -qi "aucun service" <<<"$O"

echo "[6] aide : vulns documenté"
check "vulns dans l'aide"               bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "vulns"'

echo
echo "== $pass réussis, $fail échoués =="
[[ "$fail" -eq 0 ]]
