#!/usr/bin/env bash
# tests/run.sh — lance toute la suite de tests et agrège le résultat.
# Chaque tests/test_*.sh tourne en bac à sable (dry-run + XDG/HOME temporaires)
# et sort en code ≠ 0 s'il échoue. Ce runner enchaîne tout et renvoie 1 dès
# qu'un fichier échoue — c'est le point d'entrée utilisé par la CI.
#
# Usage : ./tests/run.sh [motif]   (motif = filtre optionnel, ex. "recon")

set -uo pipefail
DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
filter="${1:-}"

reset=$'\e[0m'; red=$'\e[31m'; grn=$'\e[32m'; dim=$'\e[2m'
[[ -t 1 ]] || { reset=""; red=""; grn=""; dim=""; }

total=0; ok=0; failed=()
for t in "$DIR"/test_*.sh; do
  [[ -f "$t" ]] || continue
  name=$(basename "$t")
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  total=$((total+1))
  printf '%s───%s %s\n' "$dim" "$reset" "$name"
  if bash "$t"; then
    ok=$((ok+1))
  else
    failed+=("$name")
  fi
  echo
done

printf '%s════════════════════════════%s\n' "$dim" "$reset"
if (( ${#failed[@]} == 0 )); then
  printf '%sSuite : %d/%d fichiers OK.%s\n' "$grn" "$ok" "$total" "$reset"
  exit 0
else
  printf '%sSuite : %d/%d OK — échecs : %s%s\n' "$red" "$ok" "$total" "${failed[*]}" "$reset"
  exit 1
fi
