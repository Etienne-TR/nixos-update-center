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

  cli = writeShellApplication {
    name = command;
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
    news
    progress
  ];
  passthru = { inherit engine cli root; };
  meta.mainProgram = command;
}
