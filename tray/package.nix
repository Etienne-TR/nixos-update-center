# Icône du tray pendant la préparation (Qt seul, sans QML), provisoire en
# attendant l'interface complète.
{
  stdenv,
  pkg-config,
  qt6,
  meta,
}:
stdenv.mkDerivation {
  pname = "${meta.name}-tray";
  version = "1";
  src = ./main.cpp;
  dontUnpack = true;
  nativeBuildInputs = [
    pkg-config
    qt6.wrapQtAppsHook
  ];
  # qtwayland : plugin Wayland, ajouté au QT_PLUGIN_PATH par le wrapper.
  buildInputs = [
    qt6.qtbase
    qt6.qtwayland
  ];
  buildPhase = ''
    runHook preBuild
    $CXX -std=c++17 -O2 -fPIC $src -o ${meta.name}-tray \
      $(pkg-config --cflags --libs Qt6Widgets)
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 ${meta.name}-tray $out/bin/${meta.name}-tray
    runHook postInstall
  '';
  meta.mainProgram = "${meta.name}-tray";
}
