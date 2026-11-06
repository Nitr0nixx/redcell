#!/usr/bin/env bash
# tests/test_term.sh — abstraction du terminal (lib/term.sh). Bac à sable :
# on stube chaque émulateur sur le PATH et on règle la clé `terminal`, puis on
# vérifie le préfixe produit. Aucun terminal réel lancé.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/mode-pentest" "$TMP/bin"
# Stubs des émulateurs : présence seulement (term_bin teste command -v).
for e in foot kitty alacritty ghostty wezterm; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/$e"; chmod +x "$TMP/bin/$e"
done
export PATH="$TMP/bin:$PATH"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

# Évalue term_prefix pour une clé `terminal` donnée.
prefix_for() { # <terminal> <app-id>
  printf 'terminal = "%s"\n' "$1" > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
  bash -c '
    source "'"$REPO"'/lib/common.sh"; source "'"$REPO"'/lib/term.sh"
    term_prefix "'"$2"'"'
}
export -f prefix_for; export REPO XDG_CONFIG_HOME PATH HOME XDG_STATE_HOME

echo "== Abstraction du terminal =="

echo "[1] préfixe par émulateur (drapeaux corrects)"
check "foot : --app-id= -e"       bash -c '[ "$(prefix_for foot pentest-term)" = "foot --app-id=pentest-term -e" ]'
check "kitty : --class= (sans -e)" bash -c '[ "$(prefix_for kitty pentest-term)" = "kitty --class=pentest-term" ]'
check "alacritty : --class <id> -e" bash -c '[ "$(prefix_for alacritty pentest-term)" = "alacritty --class pentest-term -e" ]'
check "ghostty : --class= -e"     bash -c '[ "$(prefix_for ghostty pentest-vpn)" = "ghostty --class=pentest-vpn -e" ]'
check "wezterm : start --class -- " bash -c '[ "$(prefix_for wezterm pentest-term)" = "wezterm start --class pentest-term --" ]'

echo "[2] repli si le terminal configuré est absent"
# On règle un terminal inexistant ; term_bin doit retomber sur un présent.
printf 'terminal = "nexistepas"\n' > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
OUT=$(bash -c 'source "'"$REPO"'/lib/common.sh"; source "'"$REPO"'/lib/term.sh"; term_bin')
check "repli sur un émulateur présent"  bash -c 'case "$0" in foot|kitty|alacritty|ghostty|wezterm) exit 0;; *) exit 1;; esac' "$OUT"

echo "[3] repli ultime 'foot' si AUCUN terminal présent"
# Sous-shell avec PATH vide : les builtins (command -v, printf) marchent, aucun
# émulateur n'est trouvable -> term_bin doit renvoyer 'foot'.
OUT=$(
  source "$REPO/lib/common.sh"; source "$REPO/lib/term.sh"
  # shellcheck disable=SC2123  # on vide PATH exprès pour tester le repli
  PATH=""; term_bin 2>/dev/null
)
check "term_bin renvoie foot par défaut"  bash -c '[ "$0" = "foot" ]' "$OUT"

echo
echo "== $pass réussis, $fail échoués =="
[[ "$fail" -eq 0 ]]
