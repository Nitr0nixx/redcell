#!/usr/bin/env bash
# tests/test_labs.sh — liste des labs existants (pentest labs) et « on » sans nom.
# Sûrs : PENTEST_DRY_RUN=1 + XDG temporaires. Le sélecteur interactif (fzf) n'est
# pas lancé ici (stdin non-TTY) : on vérifie la liste qui l'alimente.
set -uo pipefail
ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$ROOT_DIR/bin/pentest"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config" PENTEST_DRY_RUN=1
mkdir -p "$XDG_CONFIG_HOME/mode-pentest" "$TMP/labs/ancien" "$TMP/labs/recent"
printf 'lab_root = "%s"\n' "$TMP/labs" > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
echo x > "$TMP/labs/ancien/journal.log"; touch -d '2020-01-01' "$TMP/labs/ancien/journal.log"
echo x > "$TMP/labs/recent/journal.log"
printf 'ROOM=blue\nTARGET_IP=10.10.1.2\n' > "$TMP/labs/recent/meta.env"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }
echo "== Labs existants =="
out=$("$PENTEST" labs 2>&1)
check "liste les 2 labs"             bash -c '[ "$(printf "%s\n" "$1" | wc -l)" = 2 ]' _ "$out"
check "le plus récent en premier"    bash -c 'printf "%s\n" "$1" | head -1 | grep -q "^recent"' _ "$out"
check "affiche room + cible"         grep -q "room blue · cible 10.10.1.2" <<<"$out"
check "date de dernière utilisation" grep -q "2020-01-01" <<<"$out"
check "on sans nom hors TTY -> exit 2" bash -c '"$1" on </dev/null >/dev/null 2>&1; [ $? = 2 ]' _ "$PENTEST"
rm -rf "$TMP/labs"/*
check "aucun lab -> sortie vide"     bash -c '[ -z "$("$1" labs)" ]' _ "$PENTEST"
echo; echo "Résultat : $pass réussis, $fail échoués"; [ "$fail" -eq 0 ]
