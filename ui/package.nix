# Interface : icône du tray et fenêtre QML (style KDE, qui suit kdeglobals).
{
  stdenv,
  cmake,
  kdePackages,
  makeDesktopItem,
  copyDesktopItems,
  meta,
}:
stdenv.mkDerivation {
  pname = "${meta.name}-ui";
  version = "1";
  src = ./.;
  nativeBuildInputs = [
    cmake
    kdePackages.wrapQtAppsHook
    copyDesktopItems
  ];
  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.qtwayland
    # Style org.kde.desktop et Kirigami (couleurs de kdeglobals).
    kdePackages.qqc2-desktop-style
    kdePackages.kirigami
  ];
  # cmakeFlagsArray : le titre contient des espaces.
  preConfigure = ''
    cmakeFlagsArray+=("-DAPP_NAME=${meta.name}" "-DAPP_TITLE=${meta.title}")
  '';
  desktopItems = [
    (makeDesktopItem {
      name = meta.name;
      desktopName = meta.title;
      comment = "Mettre à jour le système, Home Manager et les Flatpaks";
      exec = "${meta.name}-ui --show";
      icon = "system-software-update";
      categories = [
        "System"
        "Settings"
      ];
      startupWMClass = meta.name;
    })
  ];
  meta.mainProgram = "${meta.name}-ui";
}
