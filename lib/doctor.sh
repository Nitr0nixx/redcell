#!/usr/bin/env bash
# lib/doctor.sh — bilan de santé du mode pentest (lecture seule).
# `pentest doctor` vérifie l'installation, les dépendances et l'état runtime,
# puis affiche un rapport ✓ / ! / ✗. Il ne MODIFIE jamais rien et n'exige
# jamais sudo. Dépend de lib/common.sh (+ theme.sh, net.sh pour l'état).
#
# Code de sortie : 0 si aucun ✗ (échec bloquant), 1 sinon. Les ! (warnings)
# signalent de l'optionnel manquant sans faire échouer le bilan.

# Compteurs du bilan en cours.
_dr_ok=0; _dr_warn=0; _dr_fail=0

d_head() { printf '\n%s%s%s\n' "$_c_dim" "$1" "$_c_reset"; }

# d_line <état> <libellé> [indice]  — état ∈ ok|warn|fail
d_line() {
  local state="$1" label="$2" hint="${3:-}"
  local mark col
  case "$state" in
    ok)   mark='✓'; col="$_c_grn"; _dr_ok=$((_dr_ok+1)) ;;
    warn) mark='!'; col="$_c_ylw"; _dr_warn=$((_dr_warn+1)) ;;
    *)    mark='✗'; col="$_c_red"; _dr_fail=$((_dr_fail+1)) ;;
  esac
  printf '  %s%s%s %s' "$col" "$mark" "$_c_reset" "$label"
  [[ -n "$hint" ]] && printf ' %s(%s)%s' "$_c_dim" "$hint" "$_c_reset"
  printf '\n'
}

# d_cmd <binaire> <niveau> [indice]  — niveau ∈ fail|warn (si absent)
d_cmd() {
  local bin="$1" level="$2" hint="${3:-}"
  if command -v "$bin" >/dev/null 2>&1; then
    d_line ok "$bin"
  else
    d_line "$level" "$bin manquant" "$hint"
  fi
}

# d_link <chemin> <libellé> — vérifie qu'un lien/fichier attendu existe.
d_link() {
  local path="$1" label="$2"
  if [[ -e "$path" ]]; then d_line ok "$label"
  else d_line fail "$label introuvable" "$path"; fi
}

doctor_report() {
  local XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
  local bin_dir="$HOME/.local/bin"

  printf '%sBilan de santé — mode pentest%s\n' "$_c_grn" "$_c_reset"

  # --- Installation --------------------------------------------------------
  d_head "Installation"
  if command -v pentest >/dev/null 2>&1; then
    d_line ok "pentest sur le PATH" "$(command -v pentest)"
  else
    d_line fail "pentest absent du PATH" "lance ./install.sh, vérifie ~/.local/bin"
  fi
  d_link "$bin_dir/pentest-toggle"  "raccourci pentest-toggle"
  d_link "$bin_dir/pentest-browser" "navigateur pentest-browser"
  d_link "$XDG_CONFIG/omarchy/themes/pentest" "thème pentest"
  d_link "$PENTEST_CONFIG_DIR"      "dossier de config"
  if [[ -f "$PENTEST_CONFIG_FILE" ]]; then
    d_line ok "config.toml présent"
  else
    d_line warn "config.toml absent" "créé par ./install.sh ; les défauts s'appliquent"
  fi

  # --- Intégration bureau (Omarchy / Hyprland) -----------------------------
  d_head "Intégration bureau"
  local shelljson="$XDG_CONFIG/omarchy/shell.json"
  if [[ -e "$XDG_CONFIG/omarchy/plugins/theo.pentest" ]]; then
    if [[ -f "$shelljson" ]] && grep -q 'theo.pentest' "$shelljson" 2>/dev/null; then
      d_line ok "indicateur de barre enregistré"
    else
      d_line warn "indicateur de barre non enregistré dans shell.json" "réinstalle, ou --no-bar volontaire"
    fi
  else
    d_line warn "plugin de barre theo.pentest non lié" "optionnel"
  fi
  local bindings="$XDG_CONFIG/hypr/bindings.lua"
  if [[ -f "$bindings" ]] && grep -q 'mode-pentest' "$bindings" 2>/dev/null; then
    d_line ok "raccourci clavier posé (bindings.lua)"
  else
    d_line warn "raccourci clavier absent de bindings.lua" "optionnel ; posé par ./install.sh"
  fi

  # --- Dépendances cœur ----------------------------------------------------
  d_head "Dépendances cœur"
  d_cmd hyprctl fail "requis : mode conçu pour Hyprland"
  d_cmd omarchy fail "requis : bascule de thème"
  local _term; _term=$(term_bin)
  if command -v "$_term" >/dev/null 2>&1; then
    d_line ok "terminal : $_term" "clé 'terminal' (défaut foot)"
  else
    d_line warn "aucun terminal connu trouvé" "installe foot/kitty/alacritty/ghostty, ou règle 'terminal'"
  fi
  d_cmd tmux    warn "session persistante du lab"
  d_cmd firefox warn "navigateur isolé du lab"

  # --- Réseau (VPN / kill switch) ------------------------------------------
  d_head "Réseau"
  d_cmd openvpn warn "requis pour 'pentest vpn' (sudo pacman -S openvpn)"
  d_cmd nft     warn "requis pour le kill switch (paquet nftables)"
  d_cmd sudo    warn "VPN et nftables s'exécutent via sudo"

  # --- Reconnaissance (optionnelle) ----------------------------------------
  d_head "Reconnaissance (optionnelle)"
  local missing total
  if missing=$(tools_missing 2>/dev/null); then
    total=$(tools_missing 2>/dev/null | grep -c . || true)
    if [[ -z "$missing" ]]; then
      d_line ok "tous les outils de tools.list présents"
    else
      d_line warn "$total outil(s) de tools.list absent(s)" "détail : pentest tools ; install : pentest install"
    fi
  else
    d_line warn "liste d'outils introuvable" "config/tools.list"
  fi
  if command -v fzf >/dev/null 2>&1 || command -v gum >/dev/null 2>&1; then
    d_line ok "menu d'installation disponible (fzf/gum)"
  else
    d_line warn "ni fzf ni gum" "pentest install tombera en mode non interactif"
  fi
  d_cmd wl-copy warn "copie presse-papier (pentest ip) — paquet wl-clipboard"

  # --- État runtime --------------------------------------------------------
  d_head "État runtime"
  if is_active; then
    local lab; lab=$(active_lab)
    d_line ok "mode ACTIF" "lab : $lab"
    local cur; cur=$(theme_current 2>/dev/null || true)
    local want; want=$(cfg_get theme pentest)
    if [[ -z "$cur" || "$cur" == "$want" ]]; then
      d_line ok "thème appliqué cohérent" "${cur:-?}"
    else
      d_line warn "thème courant ≠ thème pentest" "courant : $cur, attendu : $want"
    fi
  else
    d_line ok "mode inactif" "état propre"
  fi
  local tun; tun=$(vpn_tun_ip 2>/dev/null || true)
  if [[ -n "$tun" ]]; then d_line ok "tunnel VPN présent" "$tun"
  else d_line ok "pas de tunnel VPN" "normal hors session"; fi
  if killswitch_active 2>/dev/null; then
    if [[ -n "$tun" ]]; then d_line ok "kill switch actif, tunnel présent"
    else d_line warn "kill switch actif SANS tunnel" "trafic bloqué ; pentest panic pour rétablir"; fi
  else
    d_line ok "kill switch inactif"
  fi

  # --- Cohérence de config -------------------------------------------------
  d_head "Config"
  local rtheme; rtheme=$(cfg_get restore_theme neon-city)
  if theme_exists "$rtheme" 2>/dev/null; then
    d_line ok "thème de secours installé" "restore_theme=$rtheme"
  else
    d_line warn "thème de secours introuvable" "restore_theme=$rtheme — off pourrait mal restaurer"
  fi
  local labroot="$HOME/pentest"
  if [[ -d "$labroot" ]]; then
    local perms; perms=$(stat -c '%a' "$labroot" 2>/dev/null || echo '?')
    if [[ "$perms" == "700" ]]; then d_line ok "~/pentest en 700 (privé)"
    else d_line warn "~/pentest en $perms" "attendu 700 : chmod 700 ~/pentest"; fi
  fi

  # --- Verdict -------------------------------------------------------------
  printf '\n'
  if (( _dr_fail > 0 )); then
    printf '%sVerdict : %d ✓, %d !, %d ✗ — corrige les ✗ ci-dessus.%s\n' \
      "$_c_red" "$_dr_ok" "$_dr_warn" "$_dr_fail" "$_c_reset"
    return 1
  elif (( _dr_warn > 0 )); then
    printf '%sVerdict : %d ✓, %d ! — opérationnel ; les ! sont optionnels.%s\n' \
      "$_c_ylw" "$_dr_ok" "$_dr_warn" "$_c_reset"
  else
    printf '%sVerdict : %d ✓ — tout est en place.%s\n' "$_c_grn" "$_dr_ok" "$_c_reset"
  fi
  return 0
}
