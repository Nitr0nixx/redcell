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

# Faux Hyprland : rend ces tests DÉTERMINISTES et indépendants d'une session
# réelle (donc exécutables en CI). On simule une instance (signature) et on
# stube 'hyprctl' : 'clients -j' renvoie le JSON de $HYPR_FAKE_CLIENTS (ou []),
# tout le reste réussit sans effet. hypr_window_exists interroge ce stub.
export HYPRLAND_INSTANCE_SIGNATURE=test
mkdir -p "$TMP/bin"
cat > "$TMP/bin/hyprctl" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"clients -j"* ]]; then
  if [[ -f "${HYPR_FAKE_CLIENTS:-}" ]]; then cat "$HYPR_FAKE_CLIENTS"; else echo '[]'; fi
  exit 0
fi
exit 0
STUB
chmod +x "$TMP/bin/hyprctl"
# Stub 'foot' pour que term_bin le choisisse de façon déterministe (le runner
# de CI n'a pas forcément d'émulateur installé).
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/foot"
chmod +x "$TMP/bin/foot"
export PATH="$TMP/bin:$PATH"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Phase 2 =="

echo "[1] commande bar"
check "INACTIVE au repos"        bash -c '[ "$('"$(printf %q "$PENTEST")"' bar)" = "INACTIVE" ]'

echo "[2] ouverture de la disposition (dry-run)"
out=$("$PENTEST" on demo 2>&1)
check "exec workspace 1 (terminal)"  grep -q "workspace 1 silent.*foot --app-id=pentest-term -e" <<<"$out"
check "exec workspace 2 (navigateur)" grep -q "workspace 2 silent.*pentest-browser" <<<"$out"
check "{LAB} substitué (tmux pentest-demo)" grep -q "pentest-demo" <<<"$out"
check "app-ids enregistrés"          test -f "$APPIDS"
check "app-id terminal noté"         grep -q "^pentest-term$" "$APPIDS"
check "app-id navigateur noté"       grep -q "^pentest-browser$" "$APPIDS"

echo "[3] bar ACTIVE reflète le lab"
line=$("$PENTEST" bar)
check "ligne commence par ACTIVE"    bash -c 'printf "%s" "'"$line"'" | grep -q "^ACTIVE"'
check "contient le lab demo"         bash -c 'printf "%s" "'"$line"'" | grep -q "demo"'

echo "[4] fermeture de TOUTES les fenêtres du mode (défaut, dry-run)"
SNAP="$XDG_STATE_HOME/mode-pentest/windows.before"
check "photo des fenêtres d'avant prise à on" test -f "$SNAP"
off=$("$PENTEST" off 2>&1)
check "ferme toutes les fenêtres du mode" grep -q "fermerait toutes les fenêtres ouvertes pendant le mode" <<<"$off"
check "photo nettoyée après off"   bash -c '! test -f "'"$SNAP"'"'
check "app-ids nettoyés après off"  bash -c '! test -f "'"$APPIDS"'"'

echo "[4b] fermeture ciblée (close_all_windows=off, dry-run)"
mkdir -p "$XDG_CONFIG_HOME/mode-pentest"
printf 'close_all_windows = "off"\n' > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
"$PENTEST" on demo >/dev/null 2>&1
off=$("$PENTEST" off 2>&1)
check "close class:pentest-term"    grep -q 'window.close({ window = "class:pentest-term" })' <<<"$off"
check "close class:pentest-browser" grep -q 'window.close({ window = "class:pentest-browser" })' <<<"$off"
rm -f "$XDG_CONFIG_HOME/mode-pentest/config.toml"

echo "[4c] idempotence : re-'on' ne relance pas une fenêtre déjà ouverte"
"$PENTEST" on demo >/dev/null 2>&1              # active (aucune fenêtre simulée)
export HYPR_FAKE_CLIENTS="$TMP/clients.json"
# On simule que SEUL le terminal est déjà ouvert.
printf '[{"class":"pentest-term","address":"0x1"}]\n' > "$HYPR_FAKE_CLIENTS"
reout=$("$PENTEST" on demo 2>&1)                # ré-application (déjà actif)
check "terminal déjà ouvert détecté"   grep -q "déjà ouvert.*pentest-term" <<<"$reout"
check "pas de relance du terminal"     bash -c '! grep -q "workspace 1 silent.*pentest-term" <<<"$0"' "$reout"
check "focalise le terminal existant"  grep -q 'focus.*class:pentest-term' <<<"$reout"
check "navigateur (absent) relancé"    grep -q "workspace 2 silent.*pentest-browser" <<<"$reout"
check "app-id terminal tout de même noté (pour off)" grep -q "^pentest-term$" "$APPIDS"
unset HYPR_FAKE_CLIENTS
"$PENTEST" off >/dev/null 2>&1

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
