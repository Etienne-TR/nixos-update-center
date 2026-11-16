{ meta }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (meta) name;
  cfg = config.services.${name};
  ui = pkgs.callPackage ../ui/package.nix { inherit meta; };
in
{
  options.services.${name} = {
    enable = lib.mkEnableOption "la partie Home Manager du centre de mises à jour (nouveautés Home Manager, interface) ; le moteur vient du module NixOS";
    ui.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Interface : icône dans le tray (avancement, détail au survol) et fenêtre « ${meta.title} », lancées avec la session graphique.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Nouveautés de cette génération, comparées par le moteur à chaque
        # switch (`${meta.command} --news`).
        xdg.dataFile."${name}/hm-news.json".source = config.news.json.output;
        # Pas de message « N unread and relevant news items » à chaque switch.
        news.display = "silent";
      }

      (lib.mkIf cfg.ui.enable {
        home.packages = [ ui ];
        systemd.user.services."${name}-ui" = {
          Unit = {
            Description = "Interface du centre de mises à jour (icône du tray)";
            PartOf = [ "graphical-session.target" ];
            After = [
              "graphical-session.target"
              "tray.target"
            ];
          };
          Service = {
            ExecStart = "${lib.getExe ui} --hidden";
            Restart = "on-failure";
            # update, notify-send, systemctl : PATH de la session.
            Environment = [
              "PATH=/etc/profiles/per-user/${config.home.username}/bin:${config.home.homeDirectory}/.nix-profile/bin:/run/wrappers/bin:/run/current-system/sw/bin"
            ];
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}
