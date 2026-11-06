#!/usr/bin/env bash
# lib/term.sh — abstraction du terminal. Le mode ouvre ses fenêtres (terminal du
# lab, assistant VPN, scope, lanceur) dans le terminal configuré (clé `terminal`,
# défaut `foot`), avec le bon drapeau d'app-id et d'exécution selon l'émulateur.
# Supprime l'adhérence à foot. Dépend de lib/common.sh (cfg_get).

# Terminal à utiliser : la clé `terminal` si son exécutable existe, sinon le
# premier disponible parmi les émulateurs Wayland connus, sinon `foot`.
term_bin() {
  local want; want=$(cfg_get terminal foot)
  if command -v "$want" >/dev/null 2>&1; then printf '%s' "$want"; return 0; fi
  local t
  for t in foot kitty alacritty ghostty wezterm; do
    command -v "$t" >/dev/null 2>&1 && { printf '%s' "$t"; return 0; }
  done
  printf 'foot'
}

# Préfixe de lancement pour une fenêtre d'app-id donné. Le PROGRAMME à exécuter
# suit ce préfixe (séparé par des espaces ; un app-id n'en contient jamais) :
#   foot      : --app-id=<id> -e <prog>
#   kitty     : --class=<id> <prog>          (kitty prend le programme direct)
#   alacritty : --class <id> -e <prog>
#   ghostty   : --class=<id> -e <prog>
#   wezterm   : start --class <id> -- <prog>
# L'app-id fixe la classe Wayland, indispensable au placement et à la fermeture
# ciblée (hypr_close_layout matche sur .class).
term_prefix() { # <app-id>
  local id="$1" term; term=$(term_bin)
  case "$term" in
    foot)      printf '%s --app-id=%s -e' "$term" "$id" ;;
    kitty)     printf '%s --class=%s'      "$term" "$id" ;;
    alacritty) printf '%s --class %s -e'   "$term" "$id" ;;
    ghostty)   printf '%s --class=%s -e'   "$term" "$id" ;;
    wezterm)   printf '%s start --class %s --' "$term" "$id" ;;
    *)         printf '%s -e' "$term" ;;
  esac
}
