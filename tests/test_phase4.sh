#!/usr/bin/env bash
# tests/test_phase4.sh — VPN (parsing), kill switch (ruleset), panic.
# Sûr : rien n'est exécuté en privilégié. Fonctions sourcées + CLI en dry-run.

set -uo pipefail
REPO=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)
PENTEST="$REPO/bin/pentest"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export XDG_STATE_HOME="$TMP/state" XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"

pass=0; fail=0
check() { local d="$1"; shift; if "$@"; then echo "  ✓ $d"; pass=$((pass+1)); else echo "  ✗ $d"; fail=$((fail+1)); fi; }

# shellcheck disable=SC2034  # utilisé par les libs sourcées (net.sh, lab.sh)
ROOT_DIR="$REPO"
source "$REPO/lib/common.sh"
source "$REPO/lib/net.sh"
set +eu

echo "== Phase 4 =="

echo "[1] kill switch : table DÉDIÉE et isolée"
RS=$(killswitch_ruleset "203.0.113.7" "udp" "1194")
check "table inet mode_pentest"      grep -q "table inet mode_pentest" <<<"$RS"
check "politique drop (fail closed)"  grep -q "policy drop" <<<"$RS"
check "loopback autorisé"             grep -q 'oif "lo" accept' <<<"$RS"
check "tunnel tun* autorisé"          grep -q 'oifname "tun\*" accept' <<<"$RS"
check "endpoint VPN autorisé"         grep -q "ip daddr 203.0.113.7 udp dport 1194 accept" <<<"$RS"
grep -qi ufw <<<"$RS"; ufw_hit=$?
check "n'évoque jamais ufw"           test "$ufw_hit" -ne 0
ntab=$(grep -c "^table " <<<"$RS")
check "aucune autre table touchée"    test "$ntab" -eq 1

echo "[2] parsing du .ovpn"
OVPN="$TMP/t.ovpn"; printf 'client\nremote vpn.example.com 1194\nproto udp\n' > "$OVPN"
check "remote/port/proto (udp)"  bash -c '[ "$(printf "%s" "'"$(vpn_parse_remote "$OVPN")"'")" = "vpn.example.com 1194 udp" ]'
printf 'client\nremote 198.51.100.9 443\nproto tcp-client\n' > "$OVPN"
check "proto tcp normalisé"      bash -c '[ "$(printf "%s" "'"$(vpn_parse_remote "$OVPN")"'")" = "198.51.100.9 443 tcp" ]'

echo "[3] résolution IPv4 : littéral renvoyé tel quel"
check "IP littérale inchangée"   bash -c '[ "$(printf "%s" "'"$(resolve_ipv4 198.51.100.9)"'")" = "198.51.100.9" ]'

echo "[4] chemin de config VPN par défaut"
# shellcheck disable=SC2088  # libellé affiché, pas un chemin
check "~/pentest/<lab>/vpn.ovpn"  grep -q "$HOME/pentest/demolab/vpn.ovpn" <<<"$(vpn_config_path demolab)"

echo "[5] panic (dry-run) : supprime notre table, coupe le VPN, restaure"
OUT=$(PENTEST_DRY_RUN=1 "$PENTEST" panic 2>&1)
check "supprime table inet mode_pentest" grep -q "nft delete table inet mode_pentest" <<<"$OUT"
check "coupe OpenVPN"                     grep -qi "couperait OpenVPN" <<<"$OUT"
check "réseau normal restauré"            grep -qi "réseau normal restauré" <<<"$OUT"

echo "[6] vpn status s'exécute sans lab actif"
check "vpn status exit 0"        bash -c '"'"$(printf %q "$PENTEST")"'" vpn status >/dev/null 2>&1'

echo
echo "Résultat : $pass réussis, $fail échoués"
[ "$fail" -eq 0 ]
