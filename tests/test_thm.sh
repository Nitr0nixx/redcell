#!/usr/bin/env bash
# tests/test_thm.sh — navigateur isolé -> TryHackMe + assistant de connexion VPN.
# Tout en dry-run / bac à sable : aucun tunnel réel, aucun sudo, aucune fenêtre.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"
BROWSER="$REPO/bin/pentest-browser"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/config" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$HOME/pentest" "$XDG_CONFIG_HOME/mode-pentest" "$XDG_STATE_HOME/mode-pentest" "$HOME/Downloads"

cat > "$XDG_CONFIG_HOME/mode-pentest/config.toml" <<'EOF'
lab_root = "~/pentest"
vpn_dir = "~/Downloads"
menu_integration = "off"
EOF

# Lab actif « thm ».
LAB=thm; mkdir -p "$HOME/pentest/$LAB/scope"
printf '%s\n' "$LAB" > "$XDG_STATE_HOME/mode-pentest/active"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

echo "== TryHackMe + VPN =="

echo "[1] navigateur isolé -> TryHackMe"
check "défaut TryHackMe dans le script" grep -q "tryhackme.com" "$BROWSER"
check "ouvre l'URL de démarrage (pas about:blank)" grep -q '"\$START_URL"' "$BROWSER"
check "URL passable en argument"        grep -q 'START_URL="\${2:-}"' "$BROWSER"

echo "[2] assistant VPN : aucun .ovpn"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" vpn connect 2>&1)
check "signale l'absence de .ovpn"      grep -qi "aucun fichier .ovpn" <<<"$O"
check "indique où le déposer (lab)"     grep -q "pentest/$LAB/vpn.ovpn" <<<"$O"

echo "[3] assistant VPN : un .ovpn dans le lab"
printf 'client\nremote 10.10.10.10 1194\nproto udp\n' > "$HOME/pentest/$LAB/vpn.ovpn"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" vpn connect 2>&1)
check "utilise le .ovpn du lab"         grep -q "pentest/$LAB/vpn.ovpn" <<<"$O"
check "monterait OpenVPN vers l'IP"     grep -qE "openvpn --config .* --remote 10.10.10.10 1194" <<<"$O"

echo "[4] détection dans ~/Downloads"
rm -f "$HOME/pentest/$LAB/vpn.ovpn"
printf 'client\nremote 10.9.8.7 443\nproto tcp\n' > "$HOME/Downloads/thm-theo.ovpn"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" vpn connect 2>&1)
check "trouve le .ovpn de ~/Downloads"  grep -q "Downloads/thm-theo.ovpn" <<<"$O"

echo "[5] plusieurs .ovpn : lab prioritaire (non interactif)"
printf 'client\nremote 10.10.10.10 1194\nproto udp\n' > "$HOME/pentest/$LAB/vpn.ovpn"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" vpn connect 2>&1)
check "prévient qu'il y a plusieurs configs" grep -qi "plusieurs .ovpn" <<<"$O"
check "prend le .ovpn du lab en premier" grep -qE "openvpn --config .*pentest/$LAB/vpn.ovpn" <<<"$O"

echo "[6] lanceur de menu 'open vpn'"
O=$(PENTEST_DRY_RUN=1 "$PENTEST" open vpn 2>&1)
check "ouvre un terminal -> pentest vpn connect" grep -q "pentest vpn connect" <<<"$O"

echo "[7] aide + désactivation hors lab"
check "aide mentionne vpn connect"      bash -c '"'"$PENTEST"'" help 2>&1 | grep -q "connect"'
rm -f "$XDG_STATE_HOME/mode-pentest/active"
check "connect refuse sans lab actif"   bash -c '! "'"$PENTEST"'" vpn connect >/dev/null 2>&1'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
