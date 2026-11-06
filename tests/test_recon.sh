#!/usr/bin/env bash
# tests/test_recon.sh — reconnaissance bornée au scope. Bac à sable, AUCUN scan
# réel : tout en dry-run, sauf un cas qui vérifie le refus VPN AVANT toute sonde
# (le garde-fou renvoie avant d'appeler nmap, donc rien n'est émis sur le réseau).

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
LAB=thm
mkdir -p "$HOME/pentest/$LAB/scope" "$HOME/pentest/$LAB/scans" \
         "$XDG_CONFIG_HOME/mode-pentest" "$XDG_STATE_HOME/mode-pentest"
cat > "$XDG_CONFIG_HOME/mode-pentest/config.toml" <<'CFG'
lab_root = "~/pentest"
menu_integration = "off"
manage_hosts = "off"
recon_require_vpn = "on"
recon_confirm = "on"
CFG
printf '%s\n' "$LAB" > "$XDG_STATE_HOME/mode-pentest/active"
LABDIR="$HOME/pentest/$LAB"
# Scope : une IP exacte + un CIDR /16.
printf '# Scope — %s\n\n## Cibles autorisées\n10.10.10.10\n10.10.0.0/16\n' "$LAB" \
  > "$LABDIR/scope/scope.md"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Reconnaissance (scope-gated) =="

echo "[1] Cible dans le scope (IP exacte) — dry-run"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 10.10.10.10 2>&1)
check "scope vérifié (pas de refus)"   bash -c '! grep -q "REFUS" <<<"$0"' "$O"
check "liveness (ping) planifié"       grep -q "ping -c1 -W2 10.10.10.10" <<<"$O"

echo "[2] Cible dans un CIDR du scope (10.10.0.0/16)"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 10.10.200.7 2>&1)
check "IP du /16 acceptée"             bash -c '! grep -q "REFUS" <<<"$0"' "$O"

echo "[3] Cible HORS scope — refus"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 10.20.0.1 2>&1; echo "rc=$?")
check "refuse l'IP hors scope"         grep -q "REFUS" <<<"$O"
check "cite le bon motif (périmètre)"  grep -q "périmètre autorisé" <<<"$O"
check "code de sortie non nul"         bash -c '! grep -q "rc=0" <<<"$0"' "$O"
check "ne planifie AUCUN ping"         bash -c '! grep -q "ping -c1" <<<"$0"' "$O"

echo "[4] IP publique arbitraire — refus"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 1.1.1.1 2>&1)
check "refuse une IP publique hors scope" grep -q "REFUS" <<<"$O"

echo "[5] Cible définie (TARGET_IP) autorisée même absente du scope listé"
printf 'TARGET_IP=10.99.99.99\n' > "$LABDIR/meta.env"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 2>&1)
check "la cible définie passe le garde"  bash -c '! grep -q "REFUS" <<<"$0"' "$O"
check "reco lancée sur la cible définie" grep -q "ping -c1 -W2 10.99.99.99" <<<"$O"
rm -f "$LABDIR/meta.env"

echo "[6] Aucune cible (ni argument ni TARGET_IP) — erreur claire"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 2>&1; echo "rc=$?")
check "signale l'absence de cible"     grep -q "aucune cible" <<<"$O"
check "code de sortie non nul"         bash -c '! grep -q "rc=0" <<<"$0"' "$O"

echo "[7] Garde-fou VPN (exécution réelle, mais AUCUN scan : refus avant nmap)"
# recon_require_vpn=on, pas de tunnel → recon_guard renvoie avant toute sonde.
O=$("$PENTEST" recon 10.10.10.10 --yes 2>&1; echo "rc=$?")
check "refuse sans tunnel VPN"         grep -q "pas de tunnel VPN" <<<"$O"
check "code de sortie non nul"         bash -c '! grep -q "rc=0" <<<"$0"' "$O"
check "aucun fichier de scan créé"     bash -c '[[ -z "$(ls -A "'"$LABDIR"'/scans" 2>/dev/null)" ]]'

echo "[8] recon ports : même garde-fou de scope"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon ports 10.20.0.1 2>&1)
check "ports hors scope refusé"        grep -q "REFUS" <<<"$O"

echo "[9] recon web : garde-fou de scope"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon web 8.8.8.8 80 2>&1)
check "web hors scope refusé"          grep -q "REFUS" <<<"$O"

echo "[10] recon show : vide au départ"
O=$("$PENTEST" recon show 2>&1)
check "message 'aucune reco'"          grep -q "aucune reco enregistrée" <<<"$O"

echo "[10b] échéance de scope (clause « until »)"
printf '10.55.55.55 until 2000-01-01\n10.66.66.66 until 2099-01-01\n' >> "$LABDIR/scope/scope.md"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 10.55.55.55 2>&1; echo "rc=$?")
check "cible à échéance passée refusée"    grep -q "EXPIRÉ" <<<"$O"
check "refus = code non nul"               bash -c '! grep -q "rc=0" <<<"$0"' "$O"
check "aucun ping (refus avant sonde)"     bash -c '! grep -q "ping -c1 -W2 10.55.55.55" <<<"$0"' "$O"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon 10.66.66.66 2>&1)
check "cible à échéance future acceptée"   bash -c '! grep -q "EXPIRÉ" <<<"$0"' "$O"
check "reco planifiée (ping)"              grep -q "ping -c1 -W2 10.66.66.66" <<<"$O"
O=$("$PENTEST" scope add 10.77.77.77 until pasunedate 2>&1; echo "rc=$?")
check "scope add : date illisible rejetée" grep -q "échéance illisible" <<<"$O"
# On retire les lignes d'essai pour ne pas perturber les sections suivantes.
sed -i '/^10\.55\.55\.55 until/d; /^10\.66\.66\.66 until/d' "$LABDIR/scope/scope.md"

echo "[11] CIDR : logique d'appartenance"
# Teste directement recon_in_scope via sourcing (unités fines).
O=$(PENTEST_DRY_RUN=1 bash -c '
  source "'"$REPO"'/lib/common.sh"
  source "'"$REPO"'/lib/lab.sh"; source "'"$REPO"'/lib/net.sh"; source "'"$REPO"'/lib/target.sh"
  source "'"$REPO"'/lib/recon.sh"
  _recon_ip_in_cidr 10.10.5.5 10.10.0.0/16 && echo IN16
  _recon_ip_in_cidr 10.11.5.5 10.10.0.0/16 || echo OUT16
  _recon_ip_in_cidr 192.168.1.42 192.168.1.0/24 && echo IN24
  _recon_ip_in_cidr 192.168.2.42 192.168.1.0/24 || echo OUT24
' 2>&1)
check "10.10.5.5 ∈ /16"                grep -q "IN16"  <<<"$O"
check "10.11.5.5 ∉ /16"                grep -q "OUT16" <<<"$O"
check "192.168.1.42 ∈ /24"             grep -q "IN24"  <<<"$O"
check "192.168.2.42 ∉ /24"             grep -q "OUT24" <<<"$O"

echo "[11b] parse XML nmap -> tableau structuré (ports ouverts seulement)"
cat > "$TMP/scan.xml" <<'XML'
<?xml version="1.0"?>
<nmaprun><host><ports>
<port protocol="tcp" portid="22"><state state="open"/><service name="ssh" product="OpenSSH" version="7.6p1" extrainfo="Ubuntu"/></port>
<port protocol="tcp" portid="80"><state state="open"/><service name="http" product="Apache httpd" version="2.4.29"/></port>
<port protocol="tcp" portid="23"><state state="closed"/><service name="telnet"/></port>
<port protocol="tcp" portid="445"><state state="open"/><service name="microsoft-ds"/></port>
</ports></host></nmaprun>
XML
if command -v python3 >/dev/null 2>&1; then
  O=$(bash -c '
    source "'"$REPO"'/lib/common.sh"; source "'"$REPO"'/lib/recon.sh"
    _recon_nmap_xml_tsv "'"$TMP"'/scan.xml"' 2>&1)
  check "ssh + version extraits"      bash -c 'grep -qP "^22\ttcp\tssh\tOpenSSH 7.6p1 Ubuntu$" <<<"$0"' "$O"
  check "http + version extraits"     bash -c 'grep -qP "^80\ttcp\thttp\tApache httpd 2.4.29$" <<<"$0"' "$O"
  check "service sans version -> '-'" bash -c 'grep -qP "^445\ttcp\tmicrosoft-ds\t-$" <<<"$0"' "$O"
  check "port fermé (23) exclu"       bash -c '! grep -q "telnet" <<<"$0"' "$O"
else
  echo "  (python3 absent — parser XML non testé)"
fi

echo "[11c] recon ports (nmap stubé) -> tableau structuré dans summary.md"
# Stubs déterministes : nmap écrit un .gnmap (ports) puis un .xml (services),
# ping réussit sans réseau. AUCUN scan réel ; valide le chemin de parsing.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/nmap" <<'STUB'
#!/usr/bin/env bash
out=""; mode=""; a=("$@")
for ((i=0;i<${#a[@]};i++)); do
  [[ "${a[i]}" == "-oG" ]] && { mode=g; out="${a[i+1]}"; }
  [[ "${a[i]}" == "-oX" ]] && { mode=x; out="${a[i+1]}"; }
done
if [[ "$mode" == g ]]; then
  printf 'Host: T ()\tPorts: 22/open/tcp//ssh///, 80/open/tcp//http///\n' > "$out"
elif [[ "$mode" == x ]]; then
  cat > "$out" <<'XML'
<?xml version="1.0"?>
<nmaprun><host><ports>
<port protocol="tcp" portid="22"><state state="open"/><service name="ssh" product="OpenSSH" version="7.6p1"/></port>
<port protocol="tcp" portid="80"><state state="open"/><service name="http" product="Apache httpd" version="2.4.29"/></port>
</ports></host></nmaprun>
XML
fi
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/ping"
chmod +x "$TMP/bin/nmap" "$TMP/bin/ping"
# Config permissive pour ce cas : ni VPN requis, ni confirmation.
cat > "$XDG_CONFIG_HOME/mode-pentest/config.toml" <<'CFG'
lab_root = "~/pentest"
menu_integration = "off"
manage_hosts = "off"
recon_require_vpn = "off"
recon_confirm = "off"
CFG
PATH="$TMP/bin:$PATH" "$PENTEST" recon ports 10.10.10.10 >/dev/null 2>&1
SUM="$LABDIR/scans/summary.md"
check "summary.md créé"               test -f "$SUM"
check "en-tête de tableau présent"    grep -q "| Port | Proto | Service | Version |" "$SUM"
check "ligne ssh (service+version)"   grep -q "| 22 | tcp | ssh | OpenSSH 7.6p1 |" "$SUM"
check "ligne http (service+version)"  grep -q "| 80 | tcp | http | Apache httpd 2.4.29 |" "$SUM"
check "services-latest.tsv écrit"     test -s "$LABDIR/scans/services-latest.tsv"
check "audit.log créé"                test -s "$LABDIR/audit.log"
check "audit : commande nmap tracée"  grep -q "nmap" "$LABDIR/audit.log"
check "audit : cible tracée"          grep -q "cible=10.10.10.10" "$LABDIR/audit.log"
"$PENTEST" report >/dev/null 2>&1
check "writeup reprend le tableau"    grep -q "| 22 | tcp | ssh |" "$LABDIR/report/writeup.md"

echo "[11d] rescan sans port ouvert : services-latest.tsv purgé (pas de résidu)"
# Après [11c], services-latest.tsv est non vide. Un nmap qui ne trouve plus de
# port ouvert doit l'effacer, sinon vuln_analyze re-signalerait des services
# qui ne tournent plus. Stub nmap « aucun port ouvert ».
test -s "$LABDIR/scans/services-latest.tsv"   # pré-condition (sinon test invalide)
cat > "$TMP/bin/nmap" <<'STUB'
#!/usr/bin/env bash
out=""; mode=""; a=("$@")
for ((i=0;i<${#a[@]};i++)); do
  [[ "${a[i]}" == "-oG" ]] && { mode=g; out="${a[i+1]}"; }
  [[ "${a[i]}" == "-oX" ]] && { mode=x; out="${a[i+1]}"; }
done
if [[ "$mode" == g ]]; then
  printf 'Host: T ()\tStatus: Up\n' > "$out"
elif [[ "$mode" == x ]]; then
  printf '<?xml version="1.0"?>\n<nmaprun><host><ports></ports></host></nmaprun>\n' > "$out"
fi
exit 0
STUB
chmod +x "$TMP/bin/nmap"
PATH="$TMP/bin:$PATH" "$PENTEST" recon ports 10.10.10.10 >/dev/null 2>&1
check "services-latest.tsv vidé"      bash -c '[[ ! -s "'"$LABDIR"'/scans/services-latest.tsv" ]]'

echo "[11e] recon_web honore un schéma explicite sur un port non standard"
O=$(PENTEST_DRY_RUN=1 bash -c '
  source "'"$REPO"'/lib/common.sh"
  source "'"$REPO"'/lib/lab.sh"; source "'"$REPO"'/lib/net.sh"; source "'"$REPO"'/lib/target.sh"
  source "'"$REPO"'/lib/recon.sh"
  recon_web thm 10.10.10.10 8080 https' 2>&1)
check "schéma explicite https respecté"  grep -q "https://10.10.10.10:8080/" <<<"$O"
check "pas de http:// trompeur"          bash -c '! grep -q "http://10.10.10.10:8080/" <<<"$0"' "$O"
O=$(PENTEST_DRY_RUN=1 bash -c '
  source "'"$REPO"'/lib/common.sh"
  source "'"$REPO"'/lib/lab.sh"; source "'"$REPO"'/lib/net.sh"; source "'"$REPO"'/lib/target.sh"
  source "'"$REPO"'/lib/recon.sh"
  recon_web thm 10.10.10.10 8080' 2>&1)
check "sans schéma : http déduit du port" grep -q "http://10.10.10.10:8080/" <<<"$O"

echo "[12] help : recon documenté"
check "recon dans l'aide"              bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "pentest recon"'

echo
echo "== $pass réussis, $fail échoués =="
[[ "$fail" -eq 0 ]]
