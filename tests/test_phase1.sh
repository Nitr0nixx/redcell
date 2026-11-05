#!/usr/bin/env bash
# tests/test_phase1.sh — tests de la phase 1 (on/off/status).
#
# Sûrs : tout tourne en PENTEST_DRY_RUN=1 avec des répertoires XDG temporaires,
# donc AUCUNE action système réelle (ni thème, ni DND) n'est effectuée.
# Lancement : ./tests/test_phase1.sh

set -uo pipefail

ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$ROOT_DIR/bin/pentest"

# Bac à sable temporaire.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"
export XDG_CONFIG_HOME="$TMP/config"
export PENTEST_DRY_RUN=1
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"

ACTIVE="$XDG_STATE_HOME/mode-pentest/active"
PREV="$XDG_STATE_HOME/mode-pentest/previous.env"

pass=0; fail=0
check() { # check <description> <commande booléenne...>
  local desc="$1"; shift
  if "$@"; then echo "  ✓ $desc"; pass=$((pass+1));
  else echo "  ✗ $desc"; fail=$((fail+1)); fi
}
run_p() { "$PENTEST" "$@" >/dev/null 2>&1; }       # exécute, ignore la sortie
exit_of() { "$PENTEST" "$@" >/dev/null 2>&1; echo $?; }

echo "== Phase 1 =="

echo "[1] status à froid : inactif"
check "mode inactif au départ"        bash -c '! test -f "'"$ACTIVE"'"'
check "status sort en succès"         run_p status

echo "[2] activation"
run_p on "Lab Corp"
check "fichier active créé"           test -f "$ACTIVE"
check "nom de lab nettoyé (Lab-Corp)" bash -c '[ "$(cat "'"$ACTIVE"'")" = "Lab-Corp" ]'
check "previous.env créé"             test -f "$PREV"
check "THEME sauvegardé"              grep -q '^THEME=' "$PREV"
check "DND sauvegardé"                grep -q '^DND=' "$PREV"

echo "[3] idempotence (même lab)"
# On place un marqueur : il doit survivre à un second 'on' (état original préservé).
sed -i 's/^THEME=.*/THEME=MARQUEUR/' "$PREV"
check "ré-activation même lab OK"     run_p on "Lab Corp"
check "état original préservé"        grep -q '^THEME=MARQUEUR' "$PREV"

echo "[4] refus de changer de lab à chaud"
check "on autre lab rejeté (exit!=0)" bash -c '[ "$('"$(printf %q "$PENTEST")"' on autre 2>/dev/null >/dev/null; echo $?)" != "0" ]'
check "lab inchangé"                  bash -c '[ "$(cat "'"$ACTIVE"'")" = "Lab-Corp" ]'

echo "[5] désactivation"
run_p off
check "active supprimé"               bash -c '! test -f "'"$ACTIVE"'"'
check "previous.env supprimé"         bash -c '! test -f "'"$PREV"'"'

echo "[6] off résilient (mode non actif)"
check "off sort en succès quand même" run_p off

echo "[7] erreurs d'usage"
check "on sans lab -> exit 2"         bash -c '[ "$('"$(printf %q "$PENTEST")"' on 2>/dev/null >/dev/null; echo $?)" = "2" ]'
check "commande inconnue -> exit 2"   bash -c '[ "$('"$(printf %q "$PENTEST")"' wat 2>/dev/null >/dev/null; echo $?)" = "2" ]'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
