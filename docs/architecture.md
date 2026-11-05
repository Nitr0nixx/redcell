# Architecture proposée — Mode Pentest

## Langage : Bash

Recommandation : **Bash**, pas Python.

Pourquoi : le projet orchestre surtout des commandes système (`hyprctl`, `omarchy`,
`nmcli`, `nft`, `systemctl`, manipulation de fichiers/liens). C'est le terrain naturel
de Bash, sans dépendance à installer, et ça reste lisible pour un portfolio. Si une
partie devient trop complexe (ex. parsing JSON riche), on isolera un petit helper, mais
le cœur reste Bash. On impose `set -euo pipefail`, des fonctions courtes, et
[shellcheck](https://www.shellcheck.net/) propre.

## Arborescence du projet (dans `~/projets/mode-pentest`)

```
mode-pentest/
├── bin/
│   └── pentest                 # CLI unique : on/off/status/scope/panic
├── lib/                        # fonctions Bash par domaine
│   ├── common.sh               # logs, garde-fous, backup/restore d'état
│   ├── theme.sh                # bascule + restauration du thème Omarchy
│   ├── hypr.sh                 # workspaces, layout, règles de fenêtres
│   ├── net.sh                  # VPN + kill switch nftables
│   ├── lab.sh                  # dossiers de lab, scope, journal
│   └── tools.sh                # vérification des outils (sans installer)
├── config/
│   └── mode-pentest.example.toml  # config de référence (copiée vers ~/.config)
├── templates/
│   ├── notes.md                # modèle de notes de lab
│   └── report.md               # modèle de rapport
├── shell-plugin/theo.pentest/  # plugin Quickshell : indicateur de barre
├── install.sh                  # installe/désinstalle (liens symboliques, plugin)
├── docs/                       # audit, architecture, captures
├── .gitignore
└── README.md
```

## État runtime (hors Git)

- **Config** : `~/.config/mode-pentest/config.toml` (périmètre par défaut, VPN, layout, liste d'outils).
- **Données de lab** : `~/pentest/<nom-du-lab>/` avec `chmod 700`, sous-dossiers `scope/ notes/ scans/ loot/ captures/ report/` + `journal.log`.
- **État du mode** : `~/.local/state/mode-pentest/` — sauvegarde de l'état précédent (thème, etc.) pour une **restauration fiable même après un plantage**.

Rien de sensible (clés VPN, loot, identifiants) n'entre dans Git → `.gitignore` dédié.

## Isolation des outils — comparaison

| Option | Isolation du système principal | Sudo requis | Verdict |
|---|---|---|---|
| **Paquets Arch** (`pacman`/AUR) | Faible (tout sur l'hôte) | oui (install) | Simple mais pollue l'hôte |
| **Dépôt BlackArch** | Faible + ajoute un gros dépôt tiers à l'hôte | oui | Déconseillé sur un poste perso |
| **Conteneur Distrobox + Podman rootless** | **Forte** (outils confinés, home monté à la demande) | **non** (rootless) | **Recommandé** |

**Recommandation : Distrobox + Podman rootless.** Les outils lourds (nmap, ffuf, sqlmap…)
vivent dans un conteneur jetable, l'hôte reste propre, et le rootless évite de donner les
droits root à l'outillage. `pentest on` entre dans le conteneur ; l'hôte ne garde que le
strict nécessaire (VPN, nftables qui, eux, exigent des privilèges réseau).
→ Nécessite d'installer `podman` + `distrobox` (absents). **Rien ne sera installé avant ton accord.**

Alternative minimale si tu préfères éviter les conteneurs pour commencer : paquets Arch
des seuls outils que tu choisis, listés dans la config et installés manuellement par toi.

## Sécurité — principes appliqués dès la conception

- **Scope obligatoire** par lab, affiché à chaque `pentest on` + rappel « uniquement sur des systèmes autorisés ».
- **Aucun exploit, payload, scan ou attaque** produit par ce projet : il prépare l'environnement, il ne lance rien d'offensif.
- **Kill switch = table nftables dédiée** `inet mode_pentest`, jamais de modif des règles existantes ni d'UFW. `pentest off`/`panic` suppriment **uniquement** cette table.
- **Idempotence** : chaque commande est rejouable sans casse (vérif d'état avant action).
- **`off` et `panic` robustes** : s'appuient sur l'état sauvegardé sur disque, fonctionnent même si un `on` a planté, et ne te laissent jamais sans réseau.
- **Aucune télémétrie.**

## Les 5 commandes (comportement cible)

| Commande | Effet |
|---|---|
| `pentest on <lab>` | Sauvegarde l'état, applique thème/layout/notifs, crée/ouvre le dossier du lab, démarre l'indicateur. |
| `pentest off` | Restaure l'état précédent proprement (thème, fenêtres, réseau). |
| `pentest status` | Mode, IP du VPN, état du kill switch, cible/scope. |
| `pentest scope` | Affiche ou édite le périmètre autorisé du lab courant. |
| `pentest panic` | Coupe VPN + kill switch immédiatement, restaure le réseau normal. |

## Découpage retenu pour la suite (rappel des phases du cahier des charges)

- **Phase 1** : `on`/`off`/`status` + thème + notifications + restauration + tests.
- **Phase 2** : workspaces Hyprland, tmux, profil navigateur isolé, indicateur de barre (plugin Quickshell).
- **Phase 3** : dossiers de lab, scope, modèle de notes, journal.
- **Phase 4** : VPN, kill switch, `panic`, tests de retour arrière.
- **Phase 5** : vérification des outils, raccourci Hyprland, install/désinstall, README.
