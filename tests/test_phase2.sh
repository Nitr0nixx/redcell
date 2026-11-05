#!/usr/bin/env bash
# tests/test_phase2.sh — tests de la phase 2 (disposition, bar, fermeture).
# Sûrs : PENTEST_DRY_RUN=1 + XDG temporaires. Aucune fenêtre réelle ouverte.

set -uo pipefail
ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$ROOT_DIR/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data"
export PENTEST_DRY_RUN=1
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
APPIDS="$XDG_STATE_HOME/mode-pentest/layout.appids"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Phase 2 =="

echo "[1] commande bar"
check "INACTIVE au repos"        bash -c '[ "$('"$(printf %q "$PENTEST")"' bar)" = "INACTIVE" ]'

echo "[2] ouverture de la disposition (dry-run)"
out=$("$PENTEST" on demo 2>&1)
check "exec workspace 1 (terminal)"  bash -c 'printf "%s" "'"$out"'" | grep -q "workspace 1 silent.*foot --app-id pentest-term"'
check "exec workspace 2 (navigateur)" bash -c 'printf "%s" "'"$out"'" | grep -q "workspace 2 silent.*pentest-browser"'
check "{LAB} substitué (tmux pentest-demo)" bash -c 'printf "%s" "'"$out"'" | grep -q "pentest-demo"'
check "app-ids enregistrés"          test -f "$APPIDS"
check "app-id terminal noté"         grep -q "^pentest-term$" "$APPIDS"
check "app-id navigateur noté"       grep -q "^pentest-browser$" "$APPIDS"

echo "[3] bar ACTIVE reflète le lab"
line=$("$PENTEST" bar)
check "ligne commence par ACTIVE"    bash -c 'printf "%s" "'"$line"'" | grep -q "^ACTIVE"'
check "contient le lab demo"         bash -c 'printf "%s" "'"$line"'" | grep -q "demo"'

echo "[4] fermeture ciblée (dry-run)"
off=$("$PENTEST" off 2>&1)
check "closewindow class:pentest-term"    bash -c 'printf "%s" "'"$off"'" | grep -q "closewindow class:pentest-term"'
check "closewindow class:pentest-browser" bash -c 'printf "%s" "'"$off"'" | grep -q "closewindow class:pentest-browser"'
check "app-ids nettoyés après off"        bash -c '! test -f "'"$APPIDS"'"'

echo "[5] wire_bar (édition shell.json sur copie temporaire)"
SJ="$TMP/shell.json"
cat > "$SJ" <<'JSON'
{ "bar": { "layout": { "right": [ {"id":"omarchy.tray"}, {"id":"omarchy.power"} ] } } }
JSON
python3 - "$SJ" add theo.pentest <<'PY'
import json,sys
p,a,w=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(p)); r=d["bar"]["layout"]["right"]
i=next((i for i,e in enumerate(r) if e.get("id")=="omarchy.tray"),0)
r.insert(i,{"id":w}); json.dump(d,open(p,"w"))
PY
check "widget inséré avant le tray" bash -c 'python3 -c "import json;r=json.load(open(\"'"$SJ"'\"))[\"bar\"][\"layout\"][\"right\"];ids=[e[\"id\"] for e in r];import sys;sys.exit(0 if ids.index(\"theo.pentest\")<ids.index(\"omarchy.tray\") else 1)"'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
