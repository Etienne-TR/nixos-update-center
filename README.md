# nixos-update-center

Centre de mises à jour pour une machine NixOS configurée par un flake, avec
Home Manager autonome et Flatpak (installation user).

- **`update`** : met à jour le système (nixos-rebuild switch), Home Manager
  et les Flatpaks, et éventuellement le flake (`update --help`). La mise à
  jour tourne dans l'unité utilisateur `nixos-update-center-run` : fermer le
  terminal ne l'arrête pas (`update --follow`, `update --stop`).
- **Préparation en arrière-plan** : service système
  `nixos-update-center-prebuild`, qui construit sans rien activer les
  nouvelles générations système et Home Manager en priorité minimale
  (SCHED_IDLE, nice 19, E/S idle) et télécharge les Flatpaks sans les
  déployer. `update` l'arrête et reprend à pleine vitesse ; ce qui est déjà
  construit sert tel quel. Reprise au démarrage tant que le travail n'est
  pas fini.
- **Routine** (le mercredi par défaut) : `nix flake update` avec commit de
  flake.lock, puis préparation en arrière-plan, puis notification
  « Mettre à jour ».
- **États en JSON** pour l'interface : `~/.local/state/nixos-update-center/`
  (`run.json`, `history.jsonl`, `pending.json`, `runs/*.log`),
  `/run/nixos-update-center/status.json`, `/var/lib/nixos-update-center/prebuild.json`.

- **Interface** (module Home Manager) : icône dans le tray (anneau
  d'avancement, détail au survol, menu) et fenêtre QML au style KDE, qui suit
  kdeglobals. Onglets : en attente (entrées du flake, paquets qui changent
  avec nvd, Flatpaks, Claude Desktop, commits non envoyés, préparation avec
  « Pleine vitesse » et « Arrêter »), en cours (parties, étape, avancement,
  journal), historique (exécutions et leurs journaux, générations avec retour
  arrière, nouveautés Home Manager). app_id `nixos-update-center`, pour une
  règle de fenêtre flottante.

- **Réglages de la routine** dans l'interface (onglet Réglages) : activée ou
  non, jour et heure, mise à jour du flake, Flatpaks, notification. Écrits
  dans `~/.config/nixos-update-center/settings.json` (seule la clé `routine`
  est lue) et appliqués sans rebuild ; l'horaire passe par une surcharge
  utilisateur du timer. Les valeurs par défaut viennent du module NixOS.

Le nom est défini à un seul endroit, `meta.nix`.

## Utilisation

```nix
# flake.nix
inputs.nixos-update-center = {
  url = "github:Etienne-TR/nixos-update-center";
  inputs.nixpkgs.follows = "nixpkgs";
};

# configuration NixOS
imports = [ inputs.nixos-update-center.nixosModules.default ];
services.nixos-update-center = {
  enable = true;
  flake = "/home/alice/nixos";
  user = "alice";
  schedule = "Wed 03:00:00";   # null : pas de routine
  flatpak = true;
  clean = { enable = true; keep = 3; keepSince = "7d"; };
};

# configuration Home Manager
imports = [ inputs.nixos-update-center.homeManagerModules.default ];
services.nixos-update-center.enable = true;
```

### Cohabitation avec une ancienne installation

Pendant une migration, `command.enable = false` n'installe ni `update` ni
`hm-nouveautes` (la commande reste disponible sous le nom
`nixos-update-center`) et `schedule = null` ne crée pas de routine : l'ancien
`update` et l'ancienne routine continuent seuls, l'interface et la commande
`nixos-update-center` s'utilisent à côté.

## Extras (désactivés par défaut)

Un extra ne bloque jamais la mise à jour.

- `extras.patchedPackages.<nom> = { attr; patch; marker; }` : paquet patché
  construit seul avant le switch ; si le patch ne se construit plus, le
  témoin « version sha256 » est committé et la configuration doit prendre le
  paquet d'origine en le lisant.
- `extras.voxtype.enable` : modèles de dictée Voxtype téléchargés avant le
  switch Home Manager, avec avancement.
- `extras.claudeDesktop = { enable; packageFile; }` : nouvelle version de
  Claude Desktop écrite dans `packageFile` et committée avant le switch.

## Sous-commandes du moteur

`nixos-update-center-engine run | prebuild | pending | generations | weekly |
news | boost | start-prebuild | stop-prebuild | open-update | open-journal`. Les actions root passent par
`nixos-update-center-root` (sudo sans mot de passe, arguments limités, tout
le reste lu dans `/etc/nixos-update-center/config.json`).

## Développer l'interface

`ui/dev.sh` lance une seconde interface, à côté de celle installée, qui lit le
QML dans `ui/qml` et recharge la fenêtre à chaque modification d'un fichier
`.qml` (en cas d'erreur, la fenêtre précédente reste et l'erreur s'affiche
dans le terminal). Le C++ (`ui/src`) et le moteur (`engine/`) sont construits
depuis le dépôt au lancement du script : le relancer après les avoir modifiés.
