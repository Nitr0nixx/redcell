#!/usr/bin/env bash
# tests/test_phase5.sh — vérification des outils (présent/absent), sans install.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME/mode-pentest"

# Liste de test : un outil sûrement présent (bash), un sûrement absent.
cat > "$XDG_CONFIG_HOME/mode-pentest/tools.list" <<'EOF'
#: Catégorie Test
bash
zzz-outil-inexistant-xyz
EOF

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Phase 5 =="

OUT=$("$PENTEST" tools 2>&1)
echo "[1] vérification des outils"
check "en-tête de catégorie affiché" grep -q "Catégorie Test" <<<"$OUT"
check "outil présent marqué ✓"       grep -qE "✓ bash" <<<"$OUT"
check "outil absent marqué —"        grep -qE "— zzz-outil-inexistant-xyz" <<<"$OUT"
check "résumé : 2 outils"            grep -q "2 outils" <<<"$OUT"
check "résumé : 1 présents"          grep -q "1 présents" <<<"$OUT"
check "mention aucune install auto"  grep -qi "aucune installation" <<<"$OUT"

echo "[2] option conteneurs"
C=$("$PENTEST" tools containers 2>&1)
check "recommande Distrobox+Podman rootless" grep -qi "rootless" <<<"$C"
check "ne lance rien (texte seul)"   grep -qi "rien n'est exécuté" <<<"$C"
check "mentionne BlackArch"          grep -qi "blackarch" <<<"$C"

echo "[3] aide à jour"
H=$("$PENTEST" help 2>&1)
check "aide mentionne tools"         grep -q "pentest tools" <<<"$H"
check "aide mentionne killswitch"    grep -q "pentest killswitch" <<<"$H"

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
