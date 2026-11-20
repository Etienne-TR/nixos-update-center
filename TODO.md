# À regarder plus tard

- **Style de l'interface** : le style Qt Quick « desktop » (qqc2-desktop-style)
  impose aux menus une largeur minimale, une hauteur d'entrée minimale et un
  survol en aplat de la couleur d'accent ; il a fallu les surcharger à la main
  (`RowMenuItem` dans `ui/qml/InputRow.qml`). Voir s'il vaut mieux un autre
  style, ou un thème commun à toute l'interface.
- **Mode sombre** : vérifier que l'interface suit le thème de la session
  (niri / Noctalia) et repérer les couleurs ou opacités fixées en dur qui
  passeraient mal sur fond sombre.
