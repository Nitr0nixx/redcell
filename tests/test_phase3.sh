#!/usr/bin/env bash
# tests/test_phase3.sh — dossiers de lab, scope, journal.
# Isolé : HOME + XDG temporaires. Les fonctions de lab touchent de vrais
# fichiers, mais UNIQUEMENT sous le HOME temporaire (aucun impact système).

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

# Charge les libs (ROOT_DIR requis avant lab.sh). common.sh active set -e : on
# le neutralise ensuite pour que le harnais continue malgré des retours !=0.
ROOT_DIR="$REPO"
source "$REPO/lib/common.sh"
source "$REPO/lib/lab.sh"
set +eu

echo "== Phase 3 =="

echo "[1] création du dossier de lab"
lab_init "demo-corp" >/dev/null
D="$HOME/pentest/demo-corp"
check "dossier du lab créé"      test -d "$D"
for s in scope notes scans loot captures report; do
  check "sous-dossier $s"        test -d "$D/$s"
done
check "permissions 700 sur le lab" bash -c '[ "$(stat -c %a "'"$D"'")" = "700" ]'
# shellcheck disable=SC2088  # libellé affiché, pas un chemin
check "~/pentest en 700"           bash -c '[ "$(stat -c %a "'"$HOME"'/pentest")" = "700" ]'

echo "[2] modèles instanciés"
check "scope.md créé"            test -f "$D/scope/scope.md"
check "{{LAB}} remplacé"         grep -q "demo-corp" "$D/scope/scope.md"
check "{{DATE}} remplacé"        bash -c '! grep -q "{{DATE}}" "'"$D"'/scope/scope.md"'
check "notes.md + report.md"     bash -c 'test -f "'"$D"'/notes/notes.md" && test -f "'"$D"'/report/report.md"'

echo "[3] scope : vide par défaut, puis ajout"
check "résumé 'aucune cible'"    grep -q "aucune cible" <<<"$(lab_scope_summary demo-corp)"
lab_scope_add "demo-corp" "10.10.10.0/24" >/dev/null
check "cible listée après add"   grep -q "10.10.10.0/24" <<<"$(lab_scope_targets demo-corp)"
check "résumé contient la cible"  grep -q "10.10.10.0/24" <<<"$(lab_scope_summary demo-corp)"

echo "[4] journal horodaté"
lab_journal "demo-corp" "SESSION START (mode pentest activé)" >/dev/null
check "journal.log créé"         test -f "$D/journal.log"
check "entrée horodatée"         grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$D/journal.log"
check "journal en 600"           bash -c '[ "$(stat -c %a "'"$D"'/journal.log")" = "600" ]'

echo "[5] idempotence : relancer lab_init ne casse rien ni n'écrase"
echo "MARQUEUR" >> "$D/notes/notes.md"
lab_init "demo-corp" >/dev/null
check "notes non écrasées"       grep -q "MARQUEUR" "$D/notes/notes.md"

echo "[6] CLI : scope/log refusés si aucun lab actif"
check "scope sans lab -> exit 1" bash -c '[ "$('"$(printf %q "$PENTEST")"' scope 2>/dev/null; echo $?)" = "1" ]'
check "log sans lab -> exit 1"   bash -c '[ "$('"$(printf %q "$PENTEST")"' log x 2>/dev/null; echo $?)" = "1" ]'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
