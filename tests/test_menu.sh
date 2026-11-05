#!/usr/bin/env bash
# tests/test_menu.sh — intégration au lanceur d'applications.
# Tout est confiné dans un bac à sable : aucun fichier réel n'est touché.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
SYS="$TMP/sys/applications"                    # faux répertoire « système »
export PENTEST_MENU_SYSDIRS="$SYS"
export XDG_DATA_DIRS="$TMP/sys"                 # scan limité au bac à sable
APPS="$XDG_DATA_HOME/applications"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/mode-pentest" "$SYS" "$APPS"

# Config minimale (menu activé, focus activé).
cat > "$XDG_CONFIG_HOME/mode-pentest/config.toml" <<'EOF'
menu_integration = "on"
menu_focus = "on"
lab_root = "~/pentest"
EOF

# Apps « cyber » à masquer hors mode (installées côté système).
cat > "$XDG_CONFIG_HOME/mode-pentest/menu-apps.list" <<'EOF'
burpsuite
zaproxy
EOF
# Liste blanche : on garde foot + firefox.
cat > "$XDG_CONFIG_HOME/mode-pentest/menu-keep.list" <<'EOF'
foot
firefox
EOF

mkentry() { # mkentry <dir> <id> <Name>
  cat > "$1/$2.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$3
Exec=/usr/bin/$2
EOF
}
# Côté système : 2 outils cyber + apps du quotidien + socle.
mkentry "$SYS" burpsuite "Burp Suite"
mkentry "$SYS" zaproxy   "OWASP ZAP"
mkentry "$SYS" steam     "Steam"
mkentry "$SYS" firefox   "Firefox"
mkentry "$SYS" foot      "foot"
# Une entrée LOCALE perso du quotidien (ex. Discord) à éditer en place.
mkentry "$APPS" discord  "Discord"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }
is_hidden() { grep -q '^NoDisplay=true' "$APPS/$1.desktop" 2>/dev/null; }
mark()  { grep -qF "$1" "$APPS/$2.desktop" 2>/dev/null; }

echo "== Menu =="

echo "[1] mode NORMAL (base posée par 'menu hide')"
"$PENTEST" menu hide >/dev/null 2>&1
check "burpsuite masqué (ombre)"      is_hidden burpsuite
check "ombre burpsuite marquée cyber" mark "X-ModePentest=cyber-shadow" burpsuite
check "zaproxy masqué (ombre)"        is_hidden zaproxy
check "discord perso NON masqué"      bash -c '! grep -q "^NoDisplay=true" "'"$APPS"'/discord.desktop"'
check "aucun lanceur pentest lié"     bash -c '! ls "'"$APPS"'"/pentest-*.desktop >/dev/null 2>&1'

echo "[2] mode PENTEST ('menu show' : révèle cyber + focus)"
"$PENTEST" menu show >/dev/null 2>&1
check "burpsuite révélé (ombre retirée)" bash -c '! test -e "'"$APPS"'/burpsuite.desktop"'
check "zaproxy révélé"                bash -c '! test -e "'"$APPS"'/zaproxy.desktop"'
check "lanceurs pentest liés"         bash -c 'ls "'"$APPS"'"/pentest-terminal.desktop >/dev/null 2>&1'
check "steam masqué (focus, ombre)"   is_hidden steam
check "ombre steam marquée focus"     mark "X-ModePentest=focus-shadow" steam
check "discord masqué en place"       is_hidden discord
check "discord marqué focus-local"    mark "X-ModePentest=focus-local" discord
check "sauvegarde de discord créée"   test -f "$XDG_STATE_HOME/mode-pentest/menu-backups/discord.desktop"
check "firefox GARDÉ visible"         bash -c '! grep -q "^NoDisplay=true" "'"$SYS"'/firefox.desktop" && ! test -e "'"$APPS"'/firefox.desktop"'
check "foot GARDÉ visible"            bash -c '! test -e "'"$APPS"'/foot.desktop"'

echo "[3] retour mode NORMAL ('menu hide')"
"$PENTEST" menu hide >/dev/null 2>&1
check "steam révélé (ombre focus retirée)" bash -c '! test -e "'"$APPS"'/steam.desktop"'
check "discord restauré (NoDisplay parti)" bash -c '! grep -q "^NoDisplay=true" "'"$APPS"'/discord.desktop"'
check "discord sans marqueur résiduel" bash -c '! grep -q "X-ModePentest" "'"$APPS"'/discord.desktop"'
check "burpsuite de nouveau masqué"   is_hidden burpsuite
check "lanceurs pentest retirés"      bash -c '! ls "'"$APPS"'"/pentest-*.desktop >/dev/null 2>&1'

echo "[4] nettoyage total ('menu reveal-all')"
"$PENTEST" menu show >/dev/null 2>&1          # repasse en pentest
"$PENTEST" menu reveal-all >/dev/null 2>&1
check "plus aucune ombre cyber"       bash -c '! test -e "'"$APPS"'/burpsuite.desktop"'
check "plus aucune ombre focus"       bash -c '! test -e "'"$APPS"'/steam.desktop"'
check "discord restauré après reveal-all" bash -c '! grep -q "X-ModePentest" "'"$APPS"'/discord.desktop"'
check "lanceurs retirés"              bash -c '! ls "'"$APPS"'"/pentest-*.desktop >/dev/null 2>&1'

echo "[5] respect d'une entrée perso homonyme d'un outil cyber"
mkentry "$APPS" burpsuite "Mon Burp perso"    # l'utilisateur a sa propre entrée
"$PENTEST" menu hide >/dev/null 2>&1
check "entrée perso burpsuite NON écrasée" bash -c 'grep -q "Mon Burp perso" "'"$APPS"'/burpsuite.desktop" && ! grep -q "X-ModePentest" "'"$APPS"'/burpsuite.desktop"'

echo "[6] interrupteur menu_integration=off"
sed -i 's/menu_integration = "on"/menu_integration = "off"/' "$XDG_CONFIG_HOME/mode-pentest/config.toml"
rm -f "$APPS"/burpsuite.desktop
"$PENTEST" menu hide >/dev/null 2>&1
check "rien masqué quand off"         bash -c '! test -e "'"$APPS"'/burpsuite.desktop"'
sed -i 's/menu_integration = "off"/menu_integration = "on"/' "$XDG_CONFIG_HOME/mode-pentest/config.toml"

echo "[7] aide + statut"
check "aide mentionne menu"           bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "pentest menu"'
check "statut lisible"                bash -c '"'"$PENTEST"'" menu status 2>&1 | grep -qi "Intégration menu"'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
