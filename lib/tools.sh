#!/usr/bin/env bash
# lib/tools.sh — vérification des outils (présent/absent), SANS installation.
# Liste configurable dans ~/.config/mode-pentest/tools.list.
# Dépend de lib/common.sh.

# Fichier de liste : version utilisateur si présente, sinon celle du projet.
tools_file() {
  local u="$PENTEST_CONFIG_DIR/tools.list"
  if [[ -f "$u" ]]; then printf '%s' "$u"; else printf '%s' "$ROOT_DIR/config/tools.list"; fi
}

# Affiche la liste avec, pour chaque outil, présent (✓) ou absent (—).
tools_check() {
  local f; f=$(tools_file)
  [[ -f "$f" ]] || { err "liste d'outils introuvable : $f"; return 1; }
  local present=0 absent=0 total=0 line

  while IFS= read -r line; do
    # En-tête de catégorie « #: Titre ».
    if [[ "$line" =~ ^#: ]]; then
      printf '\n%s%s%s\n' "$_c_dim" "${line#\#: }" "$_c_reset"; continue
    fi
    # Commentaires et lignes vides.
    [[ -z "${line// }" || "${line#\#}" != "$line" ]] && continue
    local tool; tool=$(printf '%s' "$line" | tr -d '[:space:]')
    [[ -n "$tool" ]] || continue
    total=$((total+1))
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %s✓%s %s\n' "$_c_grn" "$_c_reset" "$tool"; present=$((present+1))
    else
      printf '  %s—%s %s\n' "$_c_red" "$_c_reset" "$tool"; absent=$((absent+1))
    fi
  done < "$f"

  printf '\n%d outils : %d présents, %d absents.\n' "$total" "$present" "$absent"
  printf 'Aucune installation automatique. Liste : %s\n' "$f"
  printf "Isolation recommandée : « pentest tools containers ».\n"
}

# Explique l'option conteneur (Distrobox + Podman rootless). N'installe RIEN.
tools_containers() {
  cat <<'EOF'

Isolation des outils — options comparées
  1) Paquets Arch (pacman/AUR) : simple, mais installe tout sur l'hôte.
  2) Dépôt BlackArch           : très complet, mais ajoute un gros dépôt tiers à l'hôte.
  3) Distrobox + Podman rootless (RECOMMANDÉ) : les outils vivent dans un
     conteneur jetable ; l'hôte reste propre ; rootless = pas de root pour l'outillage.

Mise en place (à lancer TOI-MÊME, avec ton accord — rien n'est exécuté ici) :

  # 1. Installer Podman (rootless) et Distrobox
  sudo pacman -S --needed podman distrobox

  # 2. Créer une boîte dédiée au pentest (image BlackArch ou Kali au choix)
  distrobox create --name pentest --image docker.io/blackarchlinux/blackarch:latest
  #   (alternative Kali : --image docker.io/kalilinux/kali-rolling:latest)

  # 3. Entrer dedans et installer les outils voulus À L'INTÉRIEUR
  distrobox enter pentest
  #   puis, dans la boîte : sudo pacman -S nmap ffuf ...  (BlackArch)
  #                         ou : sudo apt install nmap ffuf ...  (Kali)

Le mode pentest n'installe ni ne lance aucun de ces outils : il prépare
seulement l'environnement.
EOF
}
