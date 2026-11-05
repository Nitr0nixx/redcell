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
| 2 | Workspaces Hyprland, tmux, Firefox isolé, indicateur de barre | ⏳ |
| 3 | Dossiers de lab, scope, notes, journal | ⏳ |
| 4 | VPN, kill switch, `panic`, retour arrière | ⏳ |
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
pentest on <nom-du-lab>   # ambiance pentest (thème rouge + DND) et marque le mode actif
pentest off               # restaure le thème et les notifications d'avant
pentest status            # mode, lab, thème, notifications (VPN/scope : phases suivantes)
```

Les commandes `scope` (phase 3) et `panic` (phase 4) sont reconnues mais pas
encore actives.

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
