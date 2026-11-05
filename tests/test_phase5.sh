#!/usr/bin/env bash
# tests/test_phase5.sh — vérification des outils (présent/absent), sans install.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME/mode-pentest"

# Liste de test (format binaire|paquet|source) : un présent (bash), deux absents
# (un officiel, un AUR) pour vérifier la répartition à l'installation.
cat > "$XDG_CONFIG_HOME/mode-pentest/tools.list" <<'EOF'
#: Catégorie Test
bash|bash|pacman
zzz-outil-inexistant-xyz|zzzpkg|pacman
zzz-aur-truc|zzzaur|aur
EOF

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== Phase 5 =="

OUT=$("$PENTEST" tools 2>&1)
echo "[1] vérification des outils"
check "en-tête de catégorie affiché" grep -q "Catégorie Test" <<<"$OUT"
check "outil présent marqué ✓"       grep -qE "✓ bash" <<<"$OUT"
check "outil absent marqué —"        grep -qE "— zzz-outil-inexistant-xyz" <<<"$OUT"
check "source affichée pour absent"  grep -q "zzzpkg · pacman" <<<"$OUT"
check "résumé : 3 outils"            grep -q "3 outils" <<<"$OUT"
check "résumé : 1 présents"          grep -q "1 présents" <<<"$OUT"
check "invite à installer"           grep -q "pentest install" <<<"$OUT"

echo "[1b] installation (dry-run, non interactif)"
I=$(PENTEST_DRY_RUN=1 "$PENTEST" install zzz-outil-inexistant-xyz zzz-aur-truc 2>&1)
check "paquet officiel via pacman"   grep -q "pacman -S --needed zzzpkg" <<<"$I"
check "paquet AUR via yay"           grep -q "yay -S --needed zzzaur" <<<"$I"
check "binaire inconnu ignoré"       bash -c 'I2=$(PENTEST_DRY_RUN=1 "'"$PENTEST"'" install nexistepas 2>&1); grep -qi "rien à installer\|inconnu" <<<"$I2"'

echo "[2] option conteneurs"
C=$("$PENTEST" tools containers 2>&1)
check "recommande Distrobox+Podman rootless" grep -qi "rootless" <<<"$C"
check "ne lance rien (texte seul)"   grep -qi "rien n'est exécuté" <<<"$C"
check "mentionne BlackArch"          grep -qi "blackarch" <<<"$C"

echo "[3] aide à jour"
H=$("$PENTEST" help 2>&1)
check "aide mentionne tools"         grep -q "pentest tools" <<<"$H"
check "aide mentionne install"       grep -q "pentest install" <<<"$H"
check "aide mentionne killswitch"    grep -q "pentest killswitch" <<<"$H"

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
