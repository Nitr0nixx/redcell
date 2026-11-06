#!/usr/bin/env bash
# lib/tools.sh — vérification ET installation guidée des outils.
# Liste configurable dans ~/.config/mode-pentest/tools.list (binaire|paquet|source).
# L'installation passe TOUJOURS par une confirmation. Dépend de lib/common.sh.

# Fichier de liste : version utilisateur si présente, sinon celle du projet.
tools_file() {
  local u="$PENTEST_CONFIG_DIR/tools.list"
  if [[ -f "$u" ]]; then printf '%s' "$u"; else printf '%s' "$ROOT_DIR/config/tools.list"; fi
}

# Itère sur les entrées (hors commentaires/en-têtes) : appelle $1 avec
# binaire, paquet, source. Les en-têtes « #: » déclenchent $2 avec le titre.
_tools_each() {
  local on_entry="$1" on_header="${2:-}" line bin pkg src
  local f; f=$(tools_file)
  [[ -f "$f" ]] || return 1
  while IFS= read -r line; do
    if [[ "$line" =~ ^#: ]]; then [[ -n "$on_header" ]] && "$on_header" "${line#\#: }"; continue; fi
    [[ -z "${line// }" || "${line#\#}" != "$line" ]] && continue
    IFS='|' read -r bin pkg src <<<"$line"
    bin=${bin// /}; pkg=${pkg// /}; src=${src// /}
    [[ -n "$bin" ]] || continue
    [[ -n "$pkg" ]] || pkg="$bin"; [[ -n "$src" ]] || src="pacman"
    "$on_entry" "$bin" "$pkg" "$src"
  done < "$f"
}

# Résout un binaire -> "paquet source" (vide si inconnu).
tools_lookup() {
  local want="$1" ; _TL_RES=""
  _tl_match() { [[ "$1" == "$want" ]] && _TL_RES="$2 $3"; }
  _tools_each _tl_match
  printf '%s' "$_TL_RES"
}

# Liste les binaires absents (un par ligne).
tools_missing() {
  _tm() { command -v "$1" >/dev/null 2>&1 || printf '%s\n' "$1"; }
  _tools_each _tm
}

# Affiche la liste avec présent (✓) / absent (—) et la source des absents.
tools_check() {
  local present=0 absent=0 total=0
  _h() { printf '\n%s%s%s\n' "$_c_dim" "$1" "$_c_reset"; }
  _e() {
    total=$((total+1))
    if command -v "$1" >/dev/null 2>&1; then
      printf '  %s✓%s %s\n' "$_c_grn" "$_c_reset" "$1"; present=$((present+1))
    else
      printf '  %s—%s %-14s %s(%s · %s)%s\n' "$_c_red" "$_c_reset" "$1" "$_c_dim" "$2" "$3" "$_c_reset"; absent=$((absent+1))
    fi
  }
  _tools_each _e _h || { err "liste d'outils introuvable"; return 1; }
  printf '\n%d outils : %d présents, %d absents.\n' "$total" "$present" "$absent"
  (( absent > 0 )) && printf 'Installer les manquants : %spentest install%s\n' "$_c_grn" "$_c_reset"
  printf 'Liste : %s\n' "$(tools_file)"
}

# Installe des outils. Sans argument : menu TUI (gum) des manquants.
# Avec arguments : installe ces binaires directement.
tools_install() {
  local wanted=("$@")

  # Sélection interactive si aucun argument.
  if [[ ${#wanted[@]} -eq 0 ]]; then
    local missing; missing=$(tools_missing)
    [[ -n "$missing" ]] || { ok "tous les outils de la liste sont déjà installés."; return 0; }
    # fzf en priorité : Espace y est lié à « cocher ». (gum 2.x ne coche plus
    # avec Espace — seulement Tab/x — d'où le bug signalé.)
    if command -v fzf >/dev/null 2>&1; then
      mapfile -t wanted < <(printf '%s\n' "$missing" | fzf --multi --layout=reverse \
        --height=~60% --border --marker='✓ ' --prompt='filtrer > ' \
        --bind 'space:toggle+down,ctrl-a:toggle-all' \
        --header $'Espace = cocher · Ctrl+A = tout · Entrée = valider · Échap = annuler\n(sans coche, Entrée prend la ligne surlignée)' \
        || true)
    elif command -v gum >/dev/null 2>&1; then
      mapfile -t wanted < <(printf '%s\n' "$missing" | gum choose --no-limit \
        --header "Tab ou x = cocher · Entrée = valider · Ctrl+C = annuler" || true)
    else
      err "ni fzf ni gum pour le menu. Donne les outils en argument : pentest install nmap ffuf"
      printf 'Manquants :\n%s\n' "$missing"; return 1
    fi
    [[ ${#wanted[@]} -gt 0 ]] || { log "aucun outil sélectionné."; return 0; }
  fi

  # Répartit les paquets par source.
  local pac=() aur=() unknown=() b res pkg src
  for b in "${wanted[@]}"; do
    [[ -n "${b// }" ]] || continue
    res=$(tools_lookup "$b")
    if [[ -z "$res" ]]; then unknown+=("$b"); continue; fi
    read -r pkg src <<<"$res"
    case "$src" in aur) aur+=("$pkg") ;; *) pac+=("$pkg") ;; esac
  done
  ((${#unknown[@]})) && warn "inconnus (ignorés) : ${unknown[*]}"
  ((${#pac[@]}+${#aur[@]})) || { err "rien à installer."; return 1; }

  echo "À installer :"
  ((${#pac[@]})) && printf '  officiel : sudo pacman -S --needed %s\n' "${pac[*]}"
  ((${#aur[@]})) && printf '  AUR      : yay -S --needed %s\n' "${aur[*]}"

  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    ((${#pac[@]})) && printf '%s[dry-run]%s sudo pacman -S --needed %s\n' "$_c_dim" "$_c_reset" "${pac[*]}"
    ((${#aur[@]})) && printf '%s[dry-run]%s yay -S --needed %s\n' "$_c_dim" "$_c_reset" "${aur[*]}"
    return 0
  fi

  # Confirmation (gum si dispo, sinon read).
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Lancer l'installation ?" || { log "annulé."; return 0; }
  else
    read -r -p "Lancer l'installation ? [o/N] " a; [[ "$a" =~ ^[oOyY]$ ]] || { log "annulé."; return 0; }
  fi

  local rc=0
  if ((${#pac[@]})); then
    log "installation officielle…"; sudo pacman -S --needed "${pac[@]}" || rc=1
  fi
  if ((${#aur[@]})); then
    if command -v yay >/dev/null 2>&1; then
      log "installation AUR (yay)…"; yay -S --needed "${aur[@]}" || rc=1
    else
      warn "yay introuvable — paquets AUR non installés : ${aur[*]}"; rc=1
    fi
  fi
  [[ $rc -eq 0 ]] && ok "installation terminée." || warn "installation terminée avec des erreurs."

  # Réconcilie le lanceur : une app cyber GUI fraîchement installée doit suivre
  # le mode (masquée hors pentest, visible pendant). Best-effort.
  if declare -F menu_reconcile >/dev/null 2>&1; then
    menu_reconcile || true
  fi
  return $rc
}

# Explique l'option conteneur (Distrobox + Podman rootless). N'installe RIEN.
tools_containers() {
  cat <<'EOF'

Isolation des outils — options comparées
  1) Paquets Arch (pacman/AUR) : simple, mais installe tout sur l'hôte.
  2) Dépôt BlackArch           : très complet, mais ajoute un gros dépôt tiers à l'hôte.
  3) Distrobox + Podman rootless (RECOMMANDÉ) : les outils vivent dans un
     conteneur jetable ; l'hôte reste propre ; rootless = pas de root pour l'outillage.

Mise en place — câblée dans `pentest box` (tu installes podman/distrobox + les
outils toi-même ; rien n'est exécuté ici) :

  sudo pacman -S --needed podman distrobox   # une fois
  pentest box create                         # crée la boîte (image BlackArch)
  pentest box shell                          # entre dedans
  #   puis, dans la boîte : sudo pacman -S nmap ffuf ...  (BlackArch)
  #   enfin, dans config.toml : recon_runner = "box"
  #   -> `pentest recon` lance alors ses outils DANS la boîte, l'hôte reste propre.

`pentest box status` montre l'état. Le mode prépare l'environnement : aucun
outil offensif n'est lancé par le projet lui-même.
EOF
}
