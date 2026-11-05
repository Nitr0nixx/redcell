# Mode Pentest

Bascule un poste **Omarchy** (Arch + Hyprland) en environnement de travail pour
labs et missions de pentest **autorisés**, via une commande unique, puis restaure
l'état d'origine à la sortie. Projet de portfolio cybersécurité : code Bash propre,
lisible et documenté.

> ⚠️ **Usage autorisé uniquement.** Ce mode prépare un environnement de travail.
> Il ne contient aucun exploit, aucune charge offensive, aucun scan automatique.
> N'utilise ce mode que sur des systèmes que tu as le droit de tester.

## État d'avancement

| Phase | Contenu | Statut |
|---|---|---|
| 0 | Audit système + architecture | ✅ |
| 1 | `on` / `off` / `status` : thème, notifications, restauration, tests | ✅ |
| 2 | Workspaces Hyprland, tmux, Firefox isolé, indicateur de barre | ✅ |
| 3 | Dossiers de lab, scope, notes, journal | ✅ |
| 4 | VPN, kill switch, `panic`, retour arrière | ✅ |
| 5 | Vérification des outils, raccourci, install/désinstall, doc | ⏳ |

## Installation

```bash
./install.sh            # crée les liens + la config (n'installe aucun paquet)
./install.sh --uninstall
```

`install.sh` lie `bin/pentest` dans `~/.local/bin`, le thème `pentest` dans
`~/.config/omarchy/themes/`, et crée `~/.config/mode-pentest/config.toml` (sans
écraser une config existante).

## Commandes (phase 1)

```bash
pentest on <nom-du-lab>     # ambiance + workspaces + dossier du lab ; mode actif
pentest off                 # restaure l'état d'avant, ferme nos fenêtres
pentest status              # mode, lab, thème, notifications, dossier, cible/scope
pentest scope               # affiche le périmètre autorisé du lab actif
pentest scope edit          # édite scope.md dans $EDITOR
pentest scope add <cible>   # ajoute une cible autorisée (ex. 10.10.10.0/24)
pentest log <texte>         # ajoute une note horodatée au journal du lab
pentest vpn up|down|status  # tunnel VPN (OpenVPN) du lab actif
pentest panic               # coupe VPN + kill switch, réseau normal immédiat
```

## VPN, kill switch et panic (phase 4)

- **VPN (OpenVPN)** : place un `.ovpn` dans `~/pentest/<lab>/vpn.ovpn` (ou
  renseigne `vpn_config`). `pentest vpn up` lance OpenVPN en arrière-plan ;
  `vpn_auto = on` le connecte dès `pentest on`. L'IP du tunnel apparaît dans
  `status` et dans l'indicateur de barre.
- **Kill switch** (`killswitch = on`) : une table nftables **dédiée**
  `inet mode_pentest`, politique **drop**, n'autorise en sortie que `lo`, le
  tunnel `tun*`, les connexions établies et l'IP:port du serveur VPN → **aucune
  fuite** du trafic de lab hors du tunnel. Elle ne touche **jamais** tes autres
  règles ni UFW ; la couper = supprimer cette seule table.
- **`pentest panic`** : coupe VPN + kill switch et restaure le réseau normal
  **immédiatement**. Fonctionne sans lab actif et même après un plantage
  (il supprime la table si elle existe, sans jamais te priver de réseau).
- `pentest off` fait toujours `net_normal` (kill switch retiré + VPN coupé).

> Prérequis : `sudo pacman -S --needed openvpn`. OpenVPN et nftables nécessitent
> `sudo`. Rien n'est lancé en privilégié sans ton action.

## Dossiers de lab, scope et journal (phase 3)

`pentest on <lab>` crée (idempotent) un dossier par lab sous `~/pentest/<lab>`
en permissions restrictives (**700**), à partir de modèles Markdown :

```
~/pentest/<lab>/
├── scope/scope.md      # périmètre AUTORISÉ (affiché à chaque activation)
├── notes/notes.md      # prise de notes
├── scans/  loot/  captures/
├── report/report.md    # squelette de rapport
├── journal.log         # sessions horodatées + notes (pentest log)
└── history.bash        # historique shell propre au lab (via HISTFILE)
```

- Le **scope** est obligatoire dans l'esprit : il est rappelé à chaque `on`.
  Édite-le (`pentest scope edit`) ou ajoute des cibles (`pentest scope add …`).
- Le **journal** reçoit automatiquement les débuts/fins de session ; `pentest
  log` y ajoute tes notes horodatées — pratique pour rédiger le rapport.
- Modèles personnalisables dans `~/.config/mode-pentest/templates/`.

## Espaces de travail, tmux et navigateur (phase 2)

À l'activation, le mode ouvre la **disposition** décrite dans un seul fichier,
`~/.config/mode-pentest/layout.conf` (modèle : `config/layout.conf`) :

```
<workspace> | <app-id> | <commande>   # {LAB} = nom du lab
```

Par défaut :
- **Workspace 1** : terminal `foot` (classe `pentest-term`) lançant une session
  **tmux** `pentest-<lab>` (attach-or-create → elle persiste). Mets tes fenêtres
  notes / scans / outils dans cette session tmux.
- **Workspace 2** : **Firefox isolé** via `pentest-browser` (profil dédié sans
  comptes perso, télémétrie/sync coupées, proxy local Burp/ZAP pré-réglé mais
  **désactivé** par défaut — voir `bin/pentest-browser`).

`pentest off` ferme **uniquement nos fenêtres** (repérées par leur app-id) ;
tmux survit donc aucun travail n'est perdu. Désactivable via `close_layout`.

**Indicateur de barre** : plugin Quickshell `theo.pentest` (une pastille rouge
« PENTEST · \<lab\> » visible quand le mode est actif, tooltip avec lab/VPN/DND).
`install.sh` l'ajoute à `shell.json` (section *right*, avant le tray) après
sauvegarde ; `--no-bar` saute cette étape, `--uninstall` le retire.

## Fonctionnement

- **Thème** : à l'activation, le thème courant est relevé puis remplacé par le
  thème rouge `pentest`. À la sortie, le thème d'origine est ré-appliqué.
- **Notifications** : le mode « ne pas déranger » d'Omarchy est activé pour
  limiter les notifications, puis restauré à l'état précédent.
- **État** : l'état d'avant activation est sauvegardé dans
  `~/.local/state/mode-pentest/previous.env`. `off` s'appuie dessus et **reste
  fiable même après un plantage** (repli sur le thème configuré dans
  `restore_theme`). Toutes les commandes sont **idempotentes**.

## Configuration

`~/.config/mode-pentest/config.toml` (modèle : `config/mode-pentest.example.toml`) :

| Clé | Rôle | Défaut |
|---|---|---|
| `theme` | thème appliqué en mode pentest | `pentest` |
| `restore_theme` | thème de secours si l'état est perdu | `neon-city` |
| `dnd` | `on` = silence les notifications | `on` |

## Développement / tests

```bash
./tests/test_phase1.sh   # tests en dry-run : aucune action réelle sur le bureau
```

Les scripts tournent en `PENTEST_DRY_RUN=1` pour afficher les actions sans les
exécuter — pratique pour tester la logique d'état sans toucher au système.

## Arborescence

Voir [`docs/architecture.md`](docs/architecture.md). Audit système :
[`docs/00-audit.md`](docs/00-audit.md).
