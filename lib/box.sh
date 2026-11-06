#!/usr/bin/env bash
# lib/box.sh — conteneur d'outils (Distrobox + Podman rootless). Jusqu'ici le
# projet ne faisait qu'EXPLIQUER cette option ; ici on la câble réellement :
#   - `pentest box create|shell|status|rm` gère une boîte jetable ;
#   - avec `recon_runner = "box"`, la reco lance ses outils DANS la boîte
#     (`distrobox enter … --`), l'hôte reste propre (promesse de l'archi doc).
# Rien n'est installé automatiquement ; sans podman/distrobox on explique. Les
# outils dans la boîte s'installent TOI-MÊME (BlackArch : sudo pacman -S …).
# Dépend de lib/common.sh.

box_name()  { cfg_get box_name "pentest"; }
box_image() { cfg_get box_image "docker.io/blackarchlinux/blackarch:latest"; }

# Distrobox + Podman présents ? (rootless : pas de root pour l'outillage.)
box_available() { command -v distrobox >/dev/null 2>&1 && command -v podman >/dev/null 2>&1; }

# La boîte <nom> existe-t-elle ? (colonne NAME de `distrobox list`.)
box_exists() { # <nom>
  command -v distrobox >/dev/null 2>&1 || return 1
  distrobox list 2>/dev/null | awk -F'|' -v want="$1" '
    NR>1 { n=$2; gsub(/^[ \t]+|[ \t]+$/,"",n); if (n==want) f=1 }
    END { exit !f }'
}

# Le runner conteneur est-il demandé ET prêt ? (recon_runner=box + boîte dispo.)
# Mémoïsé : recon_exec_prefix/recon_need l'appellent une fois PAR sonde, et
# box_exists lance `distrobox list` à chaque fois. L'état ne change pas au cours
# d'un `pentest recon`, donc on met en cache (0=prêt, 1=non) pour ce processus.
_BOX_READY_CACHE=""
box_runner_ready() {
  if [[ -z "$_BOX_READY_CACHE" ]]; then
    if [[ "$(cfg_get recon_runner host)" == "box" ]] && box_available && box_exists "$(box_name)"; then
      _BOX_READY_CACHE=ready
    else
      _BOX_READY_CACHE=no
    fi
  fi
  [[ "$_BOX_READY_CACHE" == "ready" ]]
}

# Préfixe d'exécution des sondes : vide (hôte) ou « distrobox enter <nom> -- ».
# Consommé par _recon_run / recon_need (lib/recon.sh).
recon_exec_prefix() {
  box_runner_ready && printf 'distrobox enter %s --' "$(box_name)"
}

# --- Gestion de la boîte ------------------------------------------------------

box_create() {
  if [[ "$PENTEST_DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s distrobox create --name %s --image %s\n' \
      "$_c_dim" "$_c_reset" "$(box_name)" "$(box_image)"; return 0
  fi
  if ! box_available; then
    err "podman/distrobox absents — installe-les toi-même : sudo pacman -S --needed podman distrobox"
    return 1
  fi
  if box_exists "$(box_name)"; then ok "boîte « $(box_name) » déjà présente."; return 0; fi
  log "création de la boîte « $(box_name) » (image $(box_image)) — peut télécharger une grosse image…"
  run distrobox create --name "$(box_name)" --image "$(box_image)" || { err "échec de la création."; return 1; }
  ok "boîte créée. Entre dedans (pentest box shell), puis installe tes outils : sudo pacman -S nmap ffuf …"
  ok "Active le runner conteneur : recon_runner = \"box\" dans config.toml."
}

box_shell() {
  box_available || { err "podman/distrobox absents (sudo pacman -S --needed podman distrobox)."; return 1; }
  box_exists "$(box_name)" || { err "boîte « $(box_name) » absente — crée-la : pentest box create"; return 1; }
  run distrobox enter "$(box_name)"
}

box_rm() {
  box_available || { err "distrobox absent."; return 1; }
  box_exists "$(box_name)" || { warn "boîte « $(box_name) » déjà absente."; return 0; }
  if [[ "$PENTEST_DRY_RUN" != "1" ]]; then
    local a; read -r -p "Supprimer la boîte « $(box_name) » et son contenu ? [o/N] " a
    [[ "$a" =~ ^[oOyY]$ ]] || { warn "annulé."; return 1; }
  fi
  run distrobox rm --force "$(box_name)" && ok "boîte supprimée."
}

box_status() {
  local have_db have_pm exists runner
  command -v distrobox >/dev/null 2>&1 && have_db=oui || have_db=non
  command -v podman   >/dev/null 2>&1 && have_pm=oui || have_pm=non
  box_exists "$(box_name)" && exists="présente" || exists="absente (pentest box create)"
  runner=$(cfg_get recon_runner host)
  printf 'Conteneur d'\''outils (Distrobox + Podman rootless)\n'
  printf '  distrobox    : %s\n' "$have_db"
  printf '  podman       : %s\n' "$have_pm"
  printf '  nom          : %s\n' "$(box_name)"
  printf '  image        : %s\n' "$(box_image)"
  printf '  boîte        : %s\n' "$exists"
  printf '  runner reco  : %s\n' "$runner"
  if [[ "$runner" == "box" ]] && ! box_runner_ready; then
    warn "recon_runner=box mais la boîte n'est pas prête → la reco retombera sur l'hôte."
  fi
}
