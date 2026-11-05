#!/usr/bin/env bash
# lib/net.sh — VPN (OpenVPN) + kill switch (nftables) + retour au réseau normal.
#
# PRINCIPES DE SÛRETÉ
# - Le kill switch vit dans une table nftables DÉDIÉE : « inet mode_pentest ».
#   On ne touche JAMAIS aux autres tables ni à UFW. La couper = supprimer
#   uniquement cette table (idempotent, fiable même après un plantage).
# - On ne laisse jamais l'utilisateur sans réseau : off/panic suppriment la
#   table et coupent le VPN, quoi qu'il arrive.
# - openvpn et nft exigent les privilèges root (sudo).
#
# Dépend de lib/common.sh.

NFT_TABLE_FAMILY="inet"
NFT_TABLE_NAME="mode_pentest"
VPN_PID_FILE="$PENTEST_STATE_DIR/vpn.pid"
VPN_META_FILE="$PENTEST_STATE_DIR/vpn.meta"       # iface + server (pour status)
KILLSWITCH_FLAG="$PENTEST_STATE_DIR/killswitch"

# Exécution privilégiée (sudo), ou affichage seul en dry-run.
priv() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s sudo %s\n' "$_c_dim" "$_c_reset" "$*"; return 0
  fi
  sudo "$@"
}

# --- Config VPN --------------------------------------------------------------
# Chemin du .ovpn : config explicite, sinon vpn.ovpn dans le dossier du lab.
vpn_config_path() {
  local lab="$1" c; c=$(cfg_get "vpn_config" "")
  if [[ -n "$c" ]]; then printf '%s' "${c/#\~/$HOME}"
  else printf '%s/%s/vpn.ovpn' "$(cfg_get "lab_root" "$HOME/pentest")" "$lab"; fi
}

# Extrait « remote <hôte> <port> » et « proto <proto> » d'un .ovpn.
# Renvoie : "<hôte> <port> <proto>".
vpn_parse_remote() {
  local f="$1" host port proto line
  line=$(grep -E '^[[:space:]]*remote[[:space:]]+' "$f" 2>/dev/null | head -1)
  host=$(awk '{print $2}' <<<"$line")
  port=$(awk '{print $3}' <<<"$line")
  proto=$(grep -E '^[[:space:]]*proto[[:space:]]+' "$f" 2>/dev/null | head -1 | awk '{print $2}')
  [[ -n "$port" ]]  || port=1194
  # proto dans le .ovpn : udp/tcp/tcp-client -> udp|tcp
  case "$proto" in tcp*|TCP*) proto=tcp ;; *) proto=udp ;; esac
  printf '%s %s %s' "$host" "$port" "$proto"
}

# Résout un hôte en IPv4 (pour éviter toute dépendance DNS sous kill switch).
resolve_ipv4() {
  local host="$1"
  if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s' "$host"; return 0; fi
  getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}'
}

# --- Kill switch (nftables, table dédiée) ------------------------------------
# Génère le ruleset. Politique DROP en sortie : seuls lo, le tunnel (tun*),
# les connexions établies et le serveur VPN sont autorisés -> zéro fuite.
killswitch_ruleset() { # <server_ip> <proto> <port>
  local ip="$1" proto="$2" port="$3"
  cat <<EOF
table $NFT_TABLE_FAMILY $NFT_TABLE_NAME {
  chain output {
    type filter hook output priority 0; policy drop;
    oif "lo" accept
    oifname "tun*" accept
    ct state established,related accept
    ip daddr $ip $proto dport $port accept comment "VPN endpoint"
    counter comment "mode_pentest: tout le reste est bloque"
  }
}
EOF
}

killswitch_up() { # <server_ip> <proto> <port>
  local rs; rs=$(killswitch_ruleset "$1" "$2" "$3")
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s nft -f - <<\n%s\n' "$_c_dim" "$_c_reset" "$rs"
  else
    ensure_state_dir
    local tmp; tmp=$(mktemp)
    printf '%s\n' "$rs" > "$tmp"
    priv nft -f "$tmp"; local rc=$?
    rm -f "$tmp"
    [[ $rc -eq 0 ]] || { err "kill switch : chargement nft échoué."; return 1; }
  fi
  : > "$KILLSWITCH_FLAG"
  ok "kill switch ACTIF (table $NFT_TABLE_FAMILY $NFT_TABLE_NAME)."
}

# Supprime UNIQUEMENT notre table. Idempotent : pas d'erreur si absente.
killswitch_down() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s sudo nft delete table %s %s (si présente)\n' "$_c_dim" "$_c_reset" "$NFT_TABLE_FAMILY" "$NFT_TABLE_NAME"
  else
    if sudo nft list table "$NFT_TABLE_FAMILY" "$NFT_TABLE_NAME" >/dev/null 2>&1; then
      priv nft delete table "$NFT_TABLE_FAMILY" "$NFT_TABLE_NAME" || warn "échec suppression table nft."
    fi
  fi
  rm -f "$KILLSWITCH_FLAG"
}

killswitch_active() { [[ -f "$KILLSWITCH_FLAG" ]]; }

# --- VPN (OpenVPN) -----------------------------------------------------------
vpn_up() { # <lab>
  local lab="$1" cfg; cfg=$(vpn_config_path "$lab")
  if ! command -v openvpn >/dev/null 2>&1; then
    warn "openvpn non installé (sudo pacman -S --needed openvpn) — VPN ignoré."; return 1
  fi
  if [[ ! -f "$cfg" ]]; then
    warn "config VPN introuvable : $cfg — VPN ignoré."; return 1
  fi

  local host port proto; read -r host port proto < <(vpn_parse_remote "$cfg")
  local ip; ip=$(resolve_ipv4 "$host")
  [[ -n "$ip" ]] || { err "impossible de résoudre le serveur VPN ($host)."; return 1; }
  log "VPN : serveur $host ($ip) $proto/$port"

  # Kill switch AVANT le tunnel (autorise le endpoint, bloque le reste).
  if [[ "$(cfg_get "killswitch" "off")" == "on" ]]; then
    killswitch_up "$ip" "$proto" "$port" || return 1
  fi

  ensure_state_dir
  # --remote <ip> : on force l'IP résolue (aucune dépendance DNS sous kill switch).
  priv openvpn --config "$cfg" --remote "$ip" "$port" --daemon mode-pentest \
    --writepid "$VPN_PID_FILE"
  printf 'server=%s %s/%s\n' "$ip" "$proto" "$port" > "$VPN_META_FILE"
  ok "VPN lancé (OpenVPN en arrière-plan). Vérifie 'pentest vpn status'."
}

# Coupe le VPN. Idempotent, best-effort.
vpn_down() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s couperait OpenVPN (pid %s)\n' "$_c_dim" "$_c_reset" "$VPN_PID_FILE"
    return 0
  fi
  if [[ -f "$VPN_PID_FILE" ]]; then
    local pid; pid=$(cat "$VPN_PID_FILE" 2>/dev/null)
    [[ -n "$pid" ]] && priv kill "$pid" 2>/dev/null || true
  fi
  rm -f "$VPN_PID_FILE" "$VPN_META_FILE"
}

# Interface tun + IP du tunnel (pour status/bar). Vide si pas de VPN.
vpn_tun_ip() {
  ip -4 -o addr show 2>/dev/null | awk '$2 ~ /^tun/ {print $4; exit}' | cut -d/ -f1
}

vpn_status_short() {   # pour la barre : IP du tunnel ou "—"
  local i; i=$(vpn_tun_ip); [[ -n "$i" ]] && printf '%s' "$i" || printf '—'
}

# Retour au réseau normal : kill switch coupé + VPN coupé. Ne doit jamais échouer.
net_normal() {
  killswitch_down || true
  vpn_down || true
}
