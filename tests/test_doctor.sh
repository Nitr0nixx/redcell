#!/usr/bin/env bash
# tests/test_doctor.sh — bilan de santé (pentest doctor).
# Lecture seule : doctor ne modifie jamais rien. On teste dans un bac à sable
# XDG/HOME temporaire, donc son verdict ne dépend pas de la machine de CI.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
# PATH minimal : le 'pentest' du PATH ne doit pas être trouvé -> ✗ attendu.
MINPATH="/usr/bin:/bin"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Doctor =="

echo "[1] Installation incomplète -> verdict en échec (exit 1)"
OUT=$(PATH="$MINPATH" "$PENTEST" doctor 2>&1); EC=$?
check "exit = 1 quand l'install manque"   test "$EC" -eq 1
check "signale pentest absent du PATH"    grep -q "pentest absent du PATH" <<<"$OUT"
check "au moins un ✗ affiché"             grep -q "✗" <<<"$OUT"
check "bloc Installation présent"         grep -q "Installation" <<<"$OUT"
check "bloc État runtime présent"         grep -q "État runtime" <<<"$OUT"

echo "[2] Mode inactif -> runtime propre, pas d'alerte kill switch"
check "mode inactif rapporté"             grep -q "mode inactif" <<<"$OUT"
check "pas d'alerte kill switch orphelin" bash -c '! grep -q "SANS tunnel" <<<"$0"' "$OUT"

echo "[3] Kill switch actif sans tunnel -> warning"
mkdir -p "$XDG_STATE_HOME/mode-pentest"
# Le flag du kill switch (voir lib/net.sh : KILLSWITCH_FLAG dans l'état).
: > "$XDG_STATE_HOME/mode-pentest/killswitch"
OUT2=$(PATH="$MINPATH" "$PENTEST" doctor 2>&1 || true)
check "avertit kill switch sans tunnel"   grep -q "SANS tunnel" <<<"$OUT2"

echo "[4] Lecture seule : aucun fichier d'état créé par doctor"
rm -f "$XDG_STATE_HOME/mode-pentest/killswitch"
PATH="$MINPATH" "$PENTEST" doctor >/dev/null 2>&1 || true
check "pas de fichier 'active' créé"      bash -c '! test -f "'"$XDG_STATE_HOME"'/mode-pentest/active"'

echo "[5] Aide : doctor documenté"
check "doctor dans l'aide"                bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "pentest doctor"'

echo
echo "== $pass réussis, $fail échoués =="
[[ "$fail" -eq 0 ]]
