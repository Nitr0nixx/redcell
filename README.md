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
| 5 | Vérification des outils, raccourci, install/désinstall, doc | ✅ |

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
pentest on                  # sans nom : choisir un lab existant (fzf) ou en créer un
pentest labs                # liste les labs (récents d'abord, room/cible)
pentest off                 # restaure l'état d'avant, ferme les fenêtres du mode
pentest status              # mode, lab, thème, notifications, dossier, cible/scope
pentest scope               # affiche le périmètre autorisé du lab actif
pentest scope edit          # édite scope.md dans $EDITOR
pentest scope add <cible>   # ajoute une cible autorisée (ex. 10.10.10.0/24)
pentest target <ip> [nom]   # machine cible : scope + /etc/hosts + barre/status
pentest ip                  # ton IP de tunnel VPN (LHOST), copiée au presse-papier
pentest flag <valeur> [lbl] # consigne un flag trouvé (flags.md + journal)
pentest room <nom> [url]    # renseigne la room (repris dans le writeup)
pentest report              # génère report/writeup.md (portfolio)
pentest log <texte>         # ajoute une note horodatée au journal du lab
pentest vpn connect         # assistant : choisit un .ovpn, monte le tunnel
pentest vpn up|down|status  # tunnel VPN (OpenVPN) du lab actif
pentest killswitch on|off   # kill switch nftables, indépendant du VPN
pentest panic               # coupe VPN + kill switch, réseau normal immédiat
pentest tools [containers]  # outils présents/absents ; option conteneur
pentest install [outils…]   # interface d'installation (menu TUI, confirmation)
pentest menu [status]       # adapte le lanceur d'apps au mode (voir plus bas)
```

**Raccourci** : `SUPER + SHIFT + ALT + P` bascule le mode (`pentest-toggle`) —
si actif, il le coupe ; sinon il ouvre un petit terminal qui demande le nom du
lab (avec les labs existants en suggestion). Posé/retiré par `install.sh`.

## Vérification des outils (phase 5)

`pentest tools` parcourt une liste **configurable**
(`~/.config/mode-pentest/tools.list`) et indique chaque outil **présent (✓)** ou
**absent (—)**, sans **jamais rien installer**. `pentest tools containers`
explique l'option d'isolation recommandée et donne les commandes à lancer
toi-même :

- **Distrobox + Podman rootless** (recommandé) : les outils lourds vivent dans un
  conteneur jetable (image BlackArch ou Kali), l'hôte reste propre, pas de root
  pour l'outillage. Alternatives : paquets Arch (simple mais pollue l'hôte) ou
  dépôt BlackArch (complet mais gros dépôt tiers sur l'hôte).

### Interface d'installation : `pentest install`

Menu **TUI (fzf)** pour installer facilement les outils cyber manquants :
coche ceux voulus (**Espace**, `Ctrl+A` = tout), Entrée, confirme, c'est installé.
(Repli sur gum si fzf est absent — gum 2.x coche avec **Tab**/`x`, pas Espace.) Chaque outil connaît son
**paquet** et sa **source** (dépôts officiels via `pacman`, ou AUR via `yay`) —
noms vérifiés, définis dans `tools.list`. Rien n'est installé sans confirmation.

```bash
pentest install           # menu des outils manquants
pentest install nmap ffuf # installe directement (nmap=officiel, ffuf=AUR)
```

## Lanceur d'applications adapté au mode

Le menu d'applications (walker, `SUPER + SPACE`) **reflète le mode** :

- **Hors mode (normal)** : les outils cyber (Burp, ZAP, Wireshark… — liste
  `menu-apps.list`) sont **masqués** du menu pour le garder propre.
- **En mode pentest** : ces outils **réapparaissent**, nos lanceurs
  `Pentest: …` (terminal du lab, navigateur isolé, scope, quitter) sont ajoutés,
  et — si `menu_focus = on` — **toutes les autres apps du quotidien** (jeux,
  chat, musique, webapps…) sont **masquées** pour un lanceur focalisé. Seul un
  **socle** reste visible : terminal, gestionnaire de fichiers, **Firefox**,
  réglages, éditeur, apps omarchy… (liste blanche `menu-keep.list`).

À `pentest off`, **tout est rétabli** à l'identique.

Mécanisme 100 % standard freedesktop, entièrement réversible :

- une app installée dans un répertoire système est masquée par une petite copie
  locale « ombre » (`NoDisplay=true`) qui l'occulte — révélée en retirant l'ombre ;
- une entrée **déjà locale** (propre à toi) est éditée **en place après
  sauvegarde** (`~/.local/state/mode-pentest/menu-backups/`), puis restaurée.

On ne modifie **jamais** un fichier sans l'avoir sauvegardé, et chaque
intervention porte un marqueur `X-ModePentest=` pour un retour arrière fiable
même après un plantage. Une entrée perso homonyme d'un outil cyber n'est
**jamais** écrasée.

```bash
pentest menu            # état : apps masquées/visibles, lanceurs liés
pentest menu show|hide  # force l'état pentest / normal (debug)
pentest menu reveal-all # annule toutes nos interventions (fait au --uninstall)
```

Listes éditables : `~/.config/mode-pentest/menu-apps.list` (outils cyber à
révéler en mode) et `menu-keep.list` (socle gardé pendant le focus — retires-en
Firefox si tu veux n'avoir que le navigateur isolé). Désactivable en bloc avec
`menu_integration = off`, ou focus seul avec `menu_focus = off`.

## Machine cible, flags & writeup (par room)

Confort pour enchaîner les rooms et garder une trace exploitable :

```bash
pentest target 10.10.123.45 blue   # enregistre la cible du lab actif
pentest ip                          # ton IP de tunnel (LHOST) -> presse-papier
pentest flag 'THM{...}' root        # consigne un flag (user/root/libellé libre)
pentest room "Blue" https://tryhackme.com/room/blue
pentest report                      # compile tout en report/writeup.md
```

- **`target`** mémorise l'IP (et un nom) de la box : ajoutée au scope, affichée
  dans `status` et dans la **barre** (« PENTEST · lab → ip »), et — si tu donnes
  un nom et que `manage_hosts = on` — ajoutée à **`/etc/hosts`** comme
  `ip  nom.thm` (bloc dédié, avec confirmation, **retiré à `pentest off`**).
  `pentest target` seul affiche la cible ; `pentest target clear` l'efface.
- **`ip`** affiche ton adresse `tun*` et la **copie dans le presse-papier**
  (pratique pour `LHOST` / reverse shells).
- **`flag`** horodate chaque flag dans `flags.md` + le journal.
- **`room`** renseigne nom + URL de la room (métadonnées du lab).
- **`report`** génère `report/writeup.md` (contexte, scope, flags, notes,
  journal) — **régénéré** à chaque appel ; ton `report/report.md` écrit à la
  main n'est pas touché.

## TryHackMe & connexion aux machines cibles

En mode pentest, le **navigateur isolé s'ouvre sur TryHackMe** (plateforme de
labs autorisés ; URL configurable via `browser_home`), et une **interface de
connexion VPN** s'ouvre pour atteindre facilement les machines cibles.

```bash
pentest vpn connect     # assistant guidé (aussi : lanceur « Pentest: Connexion VPN »)
```

L'assistant :

1. cherche un fichier `.ovpn` (clé `vpn_config`, dossier du lab, puis `vpn_dir`
   = `~/Downloads` par défaut — pratique pour la config téléchargée sur THM) ;
2. s'il n'en trouve pas, explique où le récupérer (page *Access* de TryHackMe)
   et propose d'ouvrir cette page dans le navigateur isolé ;
3. monte le tunnel OpenVPN avec la config choisie et **affiche l'IP du tunnel** ;
4. propose d'**enregistrer la machine cible dans le scope** (son IP), puis le
   **nom de la room** : il est enregistré (`pentest room`) et sert de nom DNS
   local `<room>.thm` dans `/etc/hosts` (confirmé, retiré à `pentest off`) ;
5. si tu le demandes, un simple test de connectivité (**un seul ping** — aucun scan).

Mise en place THM : connecte-toi sur TryHackMe → *Access* → télécharge ton
`.ovpn` → il est détecté depuis `~/Downloads` (ou dépose-le dans
`~/pentest/<lab>/vpn.ovpn`). À l'activation du mode, l'assistant s'ouvre tout
seul si tu n'es pas déjà connecté (désactivable avec `vpn_picker_on_start`).

> Rappel scope : ne te connecte et ne teste que des machines que tu es
> **autorisé** à tester (une room TryHackMe active, un lab à toi…).

## Limites connues

- **VPN non testé bout-en-bout** faute de `.ovpn` réel ; le reste du réseau
  (kill switch monté/retiré, `panic`) est validé en conditions réelles.
- Le **kill switch** a une politique *drop* : tant qu'il est actif sans tunnel,
  seules les connexions établies et le loopback passent (c'est voulu). `off` /
  `panic` le retirent toujours.
- Re-lancer `pentest on` quand le mode est déjà actif **ré-ouvre** la
  disposition (fenêtres en double possibles) ; préfère `off` puis `on`.
- Spécifique à **Omarchy/Hyprland en Lua** et au terminal **foot** : adapter
  `layout.conf` pour un autre terminal.
- Les outils de pentest eux-mêmes ne sont **pas** fournis ni lancés : ce mode
  prépare l'environnement, rien d'offensif.

## Désinstallation

```bash
./install.sh --uninstall   # retire liens, widget de barre et raccourci
```

La config (`~/.config/mode-pentest/`) et les dossiers de lab (`~/pentest/`) sont
conservés ; supprime-les à la main si tu le souhaites.

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

`pentest off` ferme **toutes les fenêtres ouvertes pendant le mode** : à
l'activation, les fenêtres existantes sont mémorisées (adresses Hyprland) et ne
sont jamais touchées ; tout ce qui est né ensuite est fermé en douceur (comme
`SUPER+W`). Le terminal d'où l'on tape `pentest off` est fermé en dernier, après
la restauration. tmux survit donc aucun travail terminal n'est perdu.
`close_all_windows = "off"` → seulement nos fenêtres (app-id, `close_layout`).

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
| `menu_integration` | `on` = outils cyber visibles seulement en mode + lanceurs | `on` |
| `menu_focus` | `on` = masque aussi les apps hors liste blanche pendant le mode | `on` |
| `browser_home` | page d'accueil du navigateur isolé | `https://tryhackme.com` |
| `vpn_dir` | dossier supplémentaire où chercher les `.ovpn` | `~/Downloads` |
| `vpn_picker_on_start` | `on` = ouvre l'assistant VPN à l'activation | `on` |
| `manage_hosts` | `on` = `pentest target <ip> <nom>` gère une entrée `/etc/hosts` | `on` |

## Développement / tests

```bash
./tests/test_phase1.sh   # tests en dry-run : aucune action réelle sur le bureau
```

Les scripts tournent en `PENTEST_DRY_RUN=1` pour afficher les actions sans les
exécuter — pratique pour tester la logique d'état sans toucher au système.

## Arborescence

Voir [`docs/architecture.md`](docs/architecture.md). Audit système :
[`docs/00-audit.md`](docs/00-audit.md).
