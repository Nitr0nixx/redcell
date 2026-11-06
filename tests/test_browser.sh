#!/usr/bin/env bash
# tests/test_browser.sh — refus auto des cookies (Consent-O-Matic) dans le
# navigateur isolé + exclusion des cibles du scope. Aucun Firefox lancé
# (PENTEST_BROWSER_PREPARE_ONLY=1), aucun téléchargement (xpi factice).
set -uo pipefail
ROOT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$ROOT_DIR/bin/pentest"; BROWSER="$ROOT_DIR/bin/pentest-browser"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config" XDG_DATA_HOME="$TMP/data"
export PATH="$ROOT_DIR/bin:$PATH" PENTEST_BROWSER_PREPARE_ONLY=1
mkdir -p "$XDG_CONFIG_HOME/mode-pentest" "$TMP/labs/r1/scope" "$XDG_DATA_HOME/mode-pentest/extensions"
printf 'lab_root = "%s"\n' "$TMP/labs" > "$XDG_CONFIG_HOME/mode-pentest/config.toml"
printf '## Cibles autorisées\n<!-- c -->\n10.10.5.7\nhttp://Box.THM:8080/admin\n10.10.9.0/30\n10.0.0.0/8\n*.lab.local\n\n## Explicitement HORS périmètre\n8.8.8.8\n' > "$TMP/labs/r1/scope/scope.md"
printf 'TARGET_HOST=r1.thm\n' > "$TMP/labs/r1/meta.env"
echo fake > "$XDG_DATA_HOME/mode-pentest/extensions/consent-o-matic.xpi"
PROF="$XDG_DATA_HOME/mode-pentest/firefox"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }
echo "== Navigateur : cookies + scope =="
h=$("$PENTEST" scope hosts r1 2>/dev/null | paste -sd' ')
check "IP du scope"                grep -qw "10.10.5.7" <<<"$h"
check "hôte nettoyé (schéma/port/casse)" grep -qw "box.thm" <<<"$h"
check "CIDR /30 développé (4 IP)"  bash -c '[ "$(tr " " "\n" <<<"$1" | grep -c "^10\.10\.9\.")" = 4 ]' _ "$h"
check "CIDR trop large ignoré"     bash -c '! grep -q "10.0.0" <<<"$1"' _ "$h"
check "joker *.lab.local + base"   bash -c 'grep -q "\*.lab.local" <<<"$1" && grep -qw "lab.local" <<<"$1"' _ "$h"
check "nom DNS de la cible (meta)" grep -qw "r1.thm" <<<"$h"
check "hors périmètre exclu"       bash -c '! grep -q "8.8.8.8" <<<"$1"' _ "$h"
"$BROWSER" r1 >/dev/null 2>&1
check "xpi posé dans le profil"    test -f "$PROF/extensions/gdpr@cavi.au.dk.xpi"
check "extensions auto-activées"   grep -q 'autoDisableScopes", 0' "$PROF/user.js"
check "cibles dans restrictedDomains" grep -q 'restrictedDomains", ".*addons.mozilla.org.*10.10.5.7.*r1.thm' "$PROF/user.js"
check "pas de restauration par défaut" grep -q 'resume_session_once", false' "$PROF/user.js"
PENTEST_BROWSER_RESTORE=1 "$BROWSER" r1 >/dev/null 2>&1
check "restauration à la relance"  grep -q 'resume_session_once", true' "$PROF/user.js"
printf 'browser_cookie_reject = "off"\n' >> "$XDG_CONFIG_HOME/mode-pentest/config.toml"
"$BROWSER" r1 >/dev/null 2>&1
check "désactivable (xpi retiré)"  bash -c '! test -f "$1/extensions/gdpr@cavi.au.dk.xpi"' _ "$PROF"
echo; echo "Résultat : $pass réussis, $fail échoués"; [ "$fail" -eq 0 ]
