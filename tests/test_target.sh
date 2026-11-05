#!/usr/bin/env bash
# tests/test_target.sh — cible / IP / flag / room / writeup. Bac à sable, aucun
# sudo (test /etc/hosts en dry-run seulement), aucune action réseau réelle.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
LAB=thm
mkdir -p "$HOME/pentest/$LAB/scope" "$HOME/pentest/$LAB/notes" \
         "$XDG_CONFIG_HOME/mode-pentest" "$XDG_STATE_HOME/mode-pentest"
printf 'lab_root = "~/pentest"\nmenu_integration = "off"\nmanage_hosts = "off"\n' \
  > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
printf '%s\n' "$LAB" > "$XDG_STATE_HOME/mode-pentest/active"
LABDIR="$HOME/pentest/$LAB"
# scope.md tel que le sèmerait 'pentest on' (lab_init), pour lab_scope_add.
printf '# Scope — %s\n\n## Cibles autorisées\n' "$LAB" > "$LABDIR/scope/scope.md"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Cible / IP / flag / room / report =="

echo "[1] target (sans nom : pas de /etc/hosts)"
O=$("$PENTEST" target 10.10.10.10 2>&1)
check "confirme l'enregistrement"     grep -q "cible enregistrée : 10.10.10.10" <<<"$O"
check "target show renvoie l'IP"      bash -c '"'"$PENTEST"'" target 2>&1 | grep -q "Cible : 10.10.10.10"'
check "IP ajoutée au scope"           grep -q "10.10.10.10" "$LABDIR/scope/scope.md"
check "bar : cible en 5e champ"       bash -c '"'"$PENTEST"'" bar 2>&1 | awk -F"\t" "{exit !(\$5==\"10.10.10.10\")}"'
check "status affiche la cible"       bash -c '"'"$PENTEST"'" status 2>&1 | grep -q "Machine cible  : 10.10.10.10"'

echo "[2] IP invalide rejetée"
check "refuse une IP invalide"        bash -c '! "'"$PENTEST"'" target pasuneip >/dev/null 2>&1'

echo "[3] /etc/hosts (dry-run, avec nom)"
sed -i 's/manage_hosts = "off"/manage_hosts = "on"/' "$XDG_CONFIG_HOME/mode-pentest/config.toml"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" target 10.10.10.10 blue 2>&1)
check "ajouterait <nom>.thm à /etc/hosts" grep -q "/etc/hosts += 10.10.10.10 blue.thm" <<<"$O"
sed -i 's/manage_hosts = "on"/manage_hosts = "off"/' "$XDG_CONFIG_HOME/mode-pentest/config.toml"

echo "[4] flag"
O=$("$PENTEST" flag 'THM{s3cr3t}' root 2>&1)
check "flag consigné"                 grep -q "flag enregistré (root)" <<<"$O"
check "flags.md contient la valeur"   grep -q 'THM{s3cr3t}' "$LABDIR/flags.md"
check "flags.md contient le libellé"  grep -q 'root' "$LABDIR/flags.md"

echo "[5] room + report (writeup)"
"$PENTEST" room "Blue" "https://tryhackme.com/room/blue" >/dev/null 2>&1
O=$("$PENTEST" report 2>&1)
check "writeup généré"                test -f "$LABDIR/report/writeup.md"
check "writeup : titre de la room"    grep -q "Writeup — Blue" "$LABDIR/report/writeup.md"
check "writeup : cible reprise"       grep -q "10.10.10.10" "$LABDIR/report/writeup.md"
check "writeup : flag repris"         grep -q 'THM{s3cr3t}' "$LABDIR/report/writeup.md"
check "writeup : URL de la room"      grep -q "tryhackme.com/room/blue" "$LABDIR/report/writeup.md"

echo "[6] ip + aide + hors lab"
check "ip ne plante pas (commande connue)" bash -c '"'"$PENTEST"'" ip 2>&1 | grep -qv "commande inconnue"'
for c in target ip flag room report; do
  check "aide mentionne $c"           bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "pentest '"$c"'"'
done
rm -f "$XDG_STATE_HOME/mode-pentest/active"
check "target refuse sans lab actif"  bash -c '! "'"$PENTEST"'" target 10.0.0.1 >/dev/null 2>&1'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
