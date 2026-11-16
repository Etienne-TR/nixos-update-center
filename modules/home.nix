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
  tray = pkgs.callPackage ../tray/package.nix { inherit meta; };
  # Moteur du système (module NixOS), qui lit /etc/<name>/config.json.
  engine = "/run/current-system/sw/bin/${name}-engine";
  statusFile = "/run/${name}/status.json";
in
{
  options.services.${name} = {
    enable = lib.mkEnableOption "la partie Home Manager du centre de mises à jour (nouveautés Home Manager, icône du tray) ; le moteur vient du module NixOS";
    tray.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Icône d'avancement dans le tray pendant la préparation en arrière-plan.";
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

      (lib.mkIf cfg.tray.enable {
        # Lancée par l'unité path quand le fichier d'avancement apparaît ;
        # se ferme quand il disparaît et notifie le résultat.
        systemd.user.services."${name}-tray" = {
          Unit = {
            Description = "Icône d'avancement de la préparation de la mise à jour";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe tray;
            Environment = [
              "PATH=/etc/profiles/per-user/${config.home.username}/bin:${config.home.homeDirectory}/.nix-profile/bin:/run/current-system/sw/bin"
              "QT_QPA_PLATFORM=wayland"
              "QT_QPA_PLATFORMTHEME="
              "PREBUILD_STATUS=${statusFile}"
              "PREBUILD_FLATPAK=/run/${name}/flatpak"
              "PREBUILD_RESULT=/var/lib/${name}/prebuild.json"
              "PREBUILD_PENDING=${config.xdg.stateHome}/${name}/prebuild-pending"
              "PREBUILD_UNIT=${name}-prebuild.service"
              "UPDATE_CENTER_ENGINE=${engine}"
            ];
          };
        };
        systemd.user.paths."${name}-tray" = {
          Unit.Description = "Icône du tray pendant la préparation de la mise à jour";
          Path.PathExists = statusFile;
          Install.WantedBy = [ "graphical-session.target" ];
        };
      })
    ]
  );
}
