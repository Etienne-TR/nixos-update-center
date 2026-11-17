# Moteur : <name>-engine, la commande `update`, <name>-root (actions root
# par sudo), <name>-progress (avancement de nix build) et hm-nouveautes.
{
  lib,
  symlinkJoin,
  writeShellApplication,
  writeScriptBin,
  python3,
  coreutils,
  findutils,
  gawk,
  gnused,
  getent,
  git,
  jq,
  curl,
  libnotify,
  util-linux,
  nvd,
  nh,
  meta,
}:
let
  inherit (meta) name command;
  subst =
    extra: file:
    lib.replaceStrings
      ([
        "@name@"
        "@title@"
        "@command@"
      ] ++ lib.attrNames extra)
      ([
        name
        meta.title
        command
      ] ++ lib.attrValues extra)
      (builtins.readFile file);

  progress = writeScriptBin "${name}-progress" (
    "#!${python3.interpreter}\n" + builtins.readFile ./progress.py
  );

  # systemctl, systemd-run, nix, nixos-rebuild, flatpak, home-manager et
  # nm-online viennent du système et du profil (PATH de l'appelant).
  engine = writeShellApplication {
    name = "${name}-engine";
    runtimeInputs = [
      coreutils
      findutils
      gawk
      gnused
      getent
      git
      jq
      curl
      libnotify
      util-linux
      nvd
      progress
    ];
    text = subst { } ./engine.sh;
  };

  # Commande principale, au nom du projet : toujours installée, utilisée
  # par l'interface et la routine. `update` (meta.command) en est un alias,
  # que le module NixOS peut ne pas installer (cohabitation avec un ancien
  # `update`).
  cli = writeShellApplication {
    inherit name;
    runtimeInputs = [
      coreutils
      jq
    ];
    text = subst { "@engine@" = "${engine}/bin/${name}-engine"; } ./cli.sh;
  };

  root = writeShellApplication {
    name = "${name}-root";
    runtimeInputs = [
      coreutils
      jq
      nh
      util-linux
    ];
    text = subst { } ./root.sh;
  };

  alias = writeShellApplication {
    name = command;
    text = ''exec ${cli}/bin/${name} "$@"'';
  };

  news = writeShellApplication {
    name = "hm-nouveautes";
    text = ''exec ${engine}/bin/${name}-engine news "$@"'';
  };
in
symlinkJoin {
  name = "${name}-engine";
  paths = [
    engine
    cli
    root
    progress
  ];
  # Installés par le module NixOS si command.enable : `update` et
  # hm-nouveautes (noms que peut déjà prendre une ancienne installation).
  passthru = {
    inherit engine cli root;
    commands = symlinkJoin {
      name = "${name}-commands";
      paths = [
        alias
        news
      ];
    };
  };
  meta.mainProgram = name;
}
