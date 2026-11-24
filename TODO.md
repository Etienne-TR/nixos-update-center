# À regarder plus tard

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
- **Distribution** : rendre l'application utilisable par d'autres personnes
  sous NixOS (options du module documentées, sans chemins ni noms propres à
  cette config, installation décrite). Recoupe l'articulation entre l'app et
  les réglages de la config NixOS faits hors de l'app (qui fait autorité,
  quoi se règle où).
