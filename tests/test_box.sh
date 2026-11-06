#!/usr/bin/env bash
# tests/test_box.sh — conteneur d'outils (lib/box.sh) + runner reco. Bac à sable :
# distrobox/podman sont STUBÉS (aucun vrai conteneur, aucun téléchargement).

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
LAB=thm
mkdir -p "$HOME/pentest/$LAB/scope" "$HOME/pentest/$LAB/scans" \
         "$XDG_CONFIG_HOME/mode-pentest" "$XDG_STATE_HOME/mode-pentest" "$TMP/bin"
printf '%s\n' "$LAB" > "$XDG_STATE_HOME/mode-pentest/active"
LABDIR="$HOME/pentest/$LAB"
printf '# Scope — %s\n\n## Cibles autorisées\n10.10.10.10\n' "$LAB" > "$LABDIR/scope/scope.md"

# Stubs : podman (présence) et distrobox (list/create/enter). 'distrobox list'
# affiche une boîte « pentest » ; 'enter … -- command -v nmap' réussit.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/podman"
cat > "$TMP/bin/distrobox" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list) printf 'ID | NAME | STATUS | IMAGE\n'; printf '123 | pentest | Up | blackarch\n' ;;
  enter) shift; # distrobox enter <name> -- <cmd...>
         while [[ "$1" != "--" && $# -gt 0 ]]; do shift; done; shift || true
         [[ "$1" == "command" ]] && exit 0 ;;   # command -v <bin> -> présent
  create) exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/podman" "$TMP/bin/distrobox"
export PATH="$TMP/bin:$PATH"

cfg() { printf '%s\n' "$1" > "$XDG_CONFIG_HOME/mode-pentest/config.toml"; }
src() { # exécute du code avec les libs chargées
  bash -c 'source "'"$REPO"'/lib/common.sh"; source "'"$REPO"'/lib/box.sh"; '"$1"
}
export -f src; export REPO PATH HOME XDG_CONFIG_HOME XDG_STATE_HOME

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Conteneur d'outils (box) =="

echo "[1] détection"
cfg 'recon_runner = "host"'
check "box_available (stubs présents)"  bash -c 'src "box_available"'
check "box_exists pentest"              bash -c 'src "box_exists pentest"'
check "box_exists absent -> faux"       bash -c '! src "box_exists nexistepas"'

echo "[2] runner : prêt seulement si recon_runner=box"
cfg 'recon_runner = "host"'
check "host : runner non actif"         bash -c '! src "box_runner_ready"'
check "host : préfixe vide"             bash -c '[ -z "$(src "recon_exec_prefix")" ]'
cfg 'recon_runner = "box"'
check "box : runner prêt"               bash -c 'src "box_runner_ready"'
check "box : préfixe distrobox"         bash -c '[ "$(src "recon_exec_prefix")" = "distrobox enter pentest --" ]'

echo "[3] création (dry-run) + status"
cfg 'recon_runner = "box"'
O=$(PENTEST_DRY_RUN=1 src 'box_create' 2>&1)
check "box create -> distrobox create"  grep -q "distrobox create --name pentest --image" <<<"$O"
O=$("$PENTEST" box status 2>&1)
check "status : boîte présente"         grep -q "présente" <<<"$O"
check "status : runner box"             grep -q "runner reco  : box" <<<"$O"

echo "[4] recon en mode box : outils lancés DANS la boîte (dry-run)"
cat > "$XDG_CONFIG_HOME/mode-pentest/config.toml" <<'CFG'
lab_root = "~/pentest"
menu_integration = "off"
recon_require_vpn = "off"
recon_confirm = "off"
recon_runner = "box"
CFG
O=$(PENTEST_DRY_RUN=1 "$PENTEST" recon ports 10.10.10.10 2>&1)
check "nmap préfixé par distrobox"      grep -q "distrobox enter pentest -- nmap" <<<"$O"

echo "[5] aide : box documenté"
check "box dans l'aide"                 bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "pentest box"'

echo
echo "== $pass réussis, $fail échoués =="
[[ "$fail" -eq 0 ]]
