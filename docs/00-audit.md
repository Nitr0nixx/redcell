# Phase 0 — Audit du système (lecture seule)

> Relevé effectué le 2026-11-05. Aucune modification apportée au système.
> Toutes les commandes utilisées sont en lecture seule.

## Système

| Élément | Valeur relevée |
|---|---|
| Omarchy | **4.0.6-1** |
| Noyau | 7.2.8-9-omarchy (Arch) |
| Compositeur | **Hyprland 0.56.2** |
| Barre / notifications | **Omarchy shell (Quickshell)** — *pas Waybar* |
| Gestionnaire réseau | NetworkManager (`nmcli` présent) |
| Agent polkit | `polkitd` actif (pour les élévations graphiques) |
| Groupes utilisateur | `theo wheel` → **pas dans le groupe `docker`** |

## Thème

- Thème courant : **Neon City** (fond « Neon Porsche 911 ») — thème cyberpunk perso, à conserver (le mode pentest devra le **sauvegarder puis le restaurer**, jamais l'écraser).
- Thèmes installés pertinents pour un mode pentest : `hackerman`, `vantablack`, `matte-black` (stock). On peut aussi créer un thème custom rouge dédié dans `~/.config/omarchy/themes/`.
- Bascule de thème : `omarchy theme set <nom>`. Le thème courant se lit via `omarchy theme bg current` (il n'existe pas de lien `current/theme` simple).

## Config Hyprland (`~/.config/hypr/`, en **Lua**)

- Fichiers : `hyprland.lua` (imports + window rules), `bindings.lua`, `monitors.lua`, `input.lua`, `looknfeel.lua`, `autostart.lua`, `hyprsunset.conf`, `xdph.conf`.
- Les overrides perso se chargent **après** les défauts Omarchy. On ajoutera donc nos règles via les helpers `o.window(...)` / `o.bind(...)`.
- `hyprctl dispatch` attend ici de la **syntaxe Lua** (ex. `hl.dsp.window.move(...)`), pas la syntaxe `.conf`.
- Validation obligatoire après toute modif : `hyprctl reload && hyprctl configerrors`.

### Raccourcis `SUPER + <lettre>` déjà occupés
`A C F G J K L O P S T V W X` (+ nombreuses combos SHIFT/ALT/CTRL).
→ **Libres et sûrs pour le mode pentest** : `SUPER + SHIFT + ALT + P`, ou un chord `SUPER + ESCAPE P`. À arbitrer en phase 2.

## Réseau / pare-feu

| Outil | État |
|---|---|
| `nft` (nftables) | présent |
| `iptables` | présent |
| `ufw` | présent (actif ? nécessite sudo pour le confirmer) |
| `wg` / `wg-quick` (WireGuard) | **absent** |
| `openvpn` | **absent** |

→ Le kill switch utilisera une **table nftables dédiée** (`inet mode_pentest`), sans jamais toucher aux règles existantes ni à UFW, comme demandé.

## Outils de pentest présents

| Présents | Absents (les plus utiles) |
|---|---|
| `netcat`, `socat`, `smbclient`, `tmux`, `chromium`, `docker` | `nmap`, `ffuf`, `gobuster`, `feroxbuster`, `nikto`, `sqlmap`, `hydra`, `john`, `hashcat`, `wireshark`, `tcpdump`, `ncat`, `proxychains4`, `responder`, `enum4linux`, **`firefox`**, `distrobox`, `podman` |

Notes :
- `firefox` est **absent** (seul `chromium` est là) → à prévoir pour le profil isolé de la phase 2, ou basculer sur un profil Chromium dédié.
- `docker` est présent mais **nécessite sudo** (utilisateur hors groupe `docker`).

## Décisions ouvertes (à valider avant la phase 1)

1. **Indicateur de barre** : la cible n'est **pas Waybar** mais le shell Quickshell. On créera donc un **plugin shell** (`theo.pentest`, comme `theo.taskmanager`) plutôt qu'un module Waybar. OK pour toi ?
2. **Isolation des outils** : voir `docs/architecture.md`, section « Isolation ». Recommandation = conteneur **Distrobox + Podman rootless**.
3. **VPN** : WireGuard ou OpenVPN ? Les deux clients sont absents ; il faudra en installer un (avec ton accord).
4. **Navigateur isolé** : Firefox (à installer) ou profil Chromium dédié (déjà présent) ?
