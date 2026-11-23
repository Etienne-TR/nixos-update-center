# À regarder plus tard

- **Style de l'interface** : le style Qt Quick « desktop » (qqc2-desktop-style)
  impose aux menus une largeur minimale, une hauteur d'entrée minimale et un
  survol en aplat de la couleur d'accent ; il a fallu les surcharger à la main
  (`RowMenuItem` dans `ui/qml/InputRow.qml`). Voir s'il vaut mieux un autre
  style, ou un thème commun à toute l'interface.
- **Mode sombre** : vérifier que l'interface suit le thème de la session
  (niri / Noctalia) et repérer les couleurs ou opacités fixées en dur qui
  passeraient mal sur fond sombre.
- **Échange sur l'architecture** : prendre un moment pour expliquer la
  séparation entre le moteur (`engine/`, commande `update`, services) et
  l'interface (`ui/`) : qui fait quoi, quels fichiers d'état les relient.
- **Ligne de commande** : voir comment utiliser l'application entièrement en
  ligne de commande (ce que `update` couvre déjà, ce qui manque).
- **Actions faites hors de l'application** : exploiter les journaux de Nix
  (générations, `nixos-rebuild`, `home-manager switch`) et de Flatpak quand ces
  commandes sont lancées à la main, pour que l'interface et le journal en
  tiennent compte.
- **Navigation** : revoir éventuellement la navigation par onglets.
