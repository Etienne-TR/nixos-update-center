# Nom du projet, à un seul endroit : il donne le nom de l'option
# (services.<name>), des unités systemd, des commandes (<name>-engine,
# <name>-root, <name>-tray), des dossiers d'état (/run/<name>,
# /var/lib/<name>, ~/.local/state/<name>) et de /etc/<name>/config.json.
# Pour renommer le projet : changer `name` ici, puis l'option dans la
# configuration qui l'utilise.
{
  name = "nixos-update-center";
  # Commande tapée dans le terminal (inchangée pour garder l'habitude).
  command = "update";
  # Nom affiché (notifications, fenêtre, info-bulle).
  title = "Mises à jour";
}
