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
  engine = pkgs.callPackage ../engine/package.nix { inherit meta; };
  root = "${engine.root}/bin/${name}-root";
  userHome = config.users.users.${cfg.user}.home;

  configFile = {
    inherit name;
    inherit (cfg)
      flake
      user
      host
      homeConfiguration
      flatpak
      push
      terminal
      ;
    inherit userHome;
    clean = { inherit (cfg.clean) enable keep keepSince; };
    pendingFile = "${userHome}/.local/state/${name}/prebuild-pending";
    rootHelper = root;
    inherit (cfg) paths;
    # Valeurs par défaut des réglages de la routine (modifiables ensuite
    # dans l'interface, ~/.config/<name>/settings.json).
    routine = {
      enabled = cfg.schedule != null;
      calendar = cfg.schedule;
      flakeUpdate = true;
      flatpak = cfg.flatpak;
    };
    extras = {
      patchedPackages = lib.mapAttrsToList (n: p: {
        name = n;
        inherit (p) attr patch marker;
      }) (lib.filterAttrs (_: p: p.enable) cfg.extras.patchedPackages);
      voxtype = cfg.extras.voxtype.enable;
      claudeDesktop = { inherit (cfg.extras.claudeDesktop) enable packageFile; };
    };
  };

  # Commandes de la session (update, home-manager) cherchées dans son PATH.
  userPath = [
    "/etc/profiles/per-user/${cfg.user}"
    "${userHome}/.nix-profile"
    "/run/wrappers"
    "/run/current-system/sw"
  ];
in
{
  options.services.${name} = {
    enable = lib.mkEnableOption "le centre de mises à jour (commande `${meta.command}`, préparation en arrière-plan, routine hebdomadaire)";

    package = lib.mkOption {
      type = lib.types.package;
      default = engine;
      readOnly = true;
      description = "Paquet du moteur.";
    };

    command.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Installer la commande `${meta.command}` (alias de `${name}`) et
        `hm-nouveautes`. false pour cohabiter avec une ancienne commande du
        même nom pendant une migration : `${name}` reste disponible.
      '';
    };

    paths = {
      system = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "nixos"
          "hosts"
        ];
        description = "Dossiers du flake (relatifs) qui ne concernent que le système : leurs changements sont rangés dans « Système NixOS » de l'interface. Ce qui est hors de tous les dossiers apparaît dans les deux parties.";
      };
      home = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "home-manager" ];
        description = "Dossiers du flake (relatifs) qui ne concernent que Home Manager.";
      };
    };

    flake = lib.mkOption {
      type = lib.types.str;
      example = "/home/alice/nixos";
      description = "Dossier du flake de la configuration (dans un dépôt git), qui définit nixosConfigurations.<host> et homeConfigurations.<homeConfiguration>.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "Utilisateur qui lance les mises à jour (propriétaire du flake, installation Flatpak user).";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Nom de cette machine dans nixosConfigurations.";
    };

    homeConfiguration = lib.mkOption {
      type = lib.types.str;
      default = cfg.user;
      defaultText = lib.literalExpression "config.services.${name}.user";
      description = "Nom de la configuration Home Manager autonome dans homeConfigurations.";
    };

    schedule = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "Wed 03:00:00";
      description = ''
        Routine (OnCalendar de systemd) : mise à jour du flake (flake.lock
        écrit, sans commit), puis préparation en arrière-plan. null :
        pas de routine.
      '';
    };

    flatpak = lib.mkOption {
      type = lib.types.bool;
      default = config.services.flatpak.enable;
      defaultText = lib.literalExpression "config.services.flatpak.enable";
      description = "Mettre à jour les Flatpaks (installation user), et les télécharger pendant la préparation.";
    };

    push = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pousser les commits (dont celui de flake.lock, fait après une application réussie) quand tous les switch ont réussi.";
    };

    clean = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nettoyer les anciennes générations (nh clean all) après un switch réussi.";
      };
      keep = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = "Nombre minimal de générations gardées.";
      };
      keepSince = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = "Générations plus récentes que cette durée toujours gardées.";
      };
    };

    terminal = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "xdg-terminal-exec" ];
      example = [
        "ghostty"
        "-e"
      ];
      description = "Terminal (et option avant la commande) ouvert par le bouton d'une notification quand l'interface n'est pas installée.";
    };

    extras = {
      patchedPackages = lib.mkOption {
        default = { };
        description = ''
          Paquets patchés avec repli : construits seuls avant le switch ;
          si le patch ne se construit plus, le fichier témoin
          « <version> <sha256 du patch> » est committé et la configuration
          doit alors prendre le paquet d'origine (en lisant ce témoin).
        '';
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "ce paquet patché" // {
                default = true;
              };
              attr = lib.mkOption {
                type = lib.types.str;
                example = "niri-patched";
                description = "Attribut du paquet patché dans le pkgs de la machine.";
              };
              patch = lib.mkOption {
                type = lib.types.str;
                description = "Chemin du patch, relatif au flake.";
              };
              marker = lib.mkOption {
                type = lib.types.str;
                description = "Chemin du fichier témoin, relatif au flake.";
              };
            };
          }
        );
      };

      voxtype.enable = lib.mkEnableOption "le téléchargement des modèles Voxtype avant le switch Home Manager, avec avancement";

      claudeDesktop = {
        enable = lib.mkEnableOption "la vérification d'une nouvelle version de Claude Desktop (écrite et committée avant le switch Home Manager)";
        packageFile = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Fichier du paquet (relatif au flake), avec `  version = \"…\";` et `sha256 = \"…\";`.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ engine ] ++ lib.optional cfg.command.enable engine.commands;
    environment.etc."${name}/config.json".text = builtins.toJSON configFile;

    # Actions root sans mot de passe : switch, retour arrière, nettoyage,
    # pleine vitesse de la préparation (tout est lu dans config.json).
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = root;
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Démarrer et arrêter la préparation sans mot de passe (routine, update,
    # interface).
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "${name}-prebuild.service" &&
            subject.user == "${cfg.user}" &&
            (action.lookup("verb") == "start" || action.lookup("verb") == "stop")) {
          return polkit.Result.YES;
        }
      });
    '';

    # Préparation en arrière-plan. Exécutée par root sur le store local
    # (NIX_REMOTE=local), et non par nix-daemon : les constructions sont des
    # processus de ce service et héritent de sa priorité minimale. Reprise
    # au démarrage tant que le témoin existe.
    systemd.services."${name}-prebuild" = {
      description = "Préparation en arrière-plan de la mise à jour (construction Nix et téléchargement Flatpak, sans activation)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "nix-daemon.service"
      ];
      unitConfig.ConditionPathExists = configFile.pendingFile;
      restartIfChanged = false;
      path = [
        config.nix.package
        config.services.flatpak.package
      ];
      environment = {
        NIX_REMOTE = "local";
        HOME = "/root";
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${engine}/bin/${name}-engine prebuild";
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0755";
        StateDirectory = name;
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        CPUWeight = 1;
        IOWeight = 1;
        TimeoutStopSec = "30s";
      };
    };

    systemd.user.services."${name}-weekly" = lib.mkIf (cfg.schedule != null) {
      description = "Routine des mises à jour (flake, puis préparation en arrière-plan)";
      unitConfig.ConditionUser = cfg.user;
      path = userPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${engine}/bin/${name}-engine weekly";
        # La notification attend un clic.
        TimeoutStartSec = "infinity";
      };
    };

    systemd.user.timers."${name}-weekly" = lib.mkIf (cfg.schedule != null) {
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig = {
        OnCalendar = cfg.schedule;
        # Heure manquée (ordinateur éteint) : rattrapée au démarrage suivant.
        Persistent = true;
      };
    };
  };
}
