#!/usr/bin/env bash
# Interface en mode développement : le QML est lu dans ui/qml et la fenêtre
# rechargée à chaque modification d'un fichier .qml. Le C++ est celui de la
# dernière construction (relancer ce script après un changement de ui/src),
# le moteur celui du système. Tourne à côté de l'interface installée.
set -euo pipefail
cd "$(dirname "$0")/.."
# Lancé sans terminal (lanceur) : sortie, dont les erreurs QML, dans un
# fichier.
if [ ! -t 1 ]; then
  log="${XDG_STATE_HOME:-$HOME/.local/state}/nixos-update-center/dev.log"
  mkdir -p "$(dirname "$log")"
  exec >"$log" 2>&1
fi
# Même nixpkgs (donc même Qt) que la config installée, pour que le thème
# KDE de la session se charge.
lock="${NIXOS_CONFIG_FLAKE:-$HOME/.config/nixos/etienne-flake}/flake.lock"
override=()
if rev=$(jq -r '.nodes.nixpkgs.locked.rev // empty' "$lock" 2>/dev/null) && [ -n "$rev" ]; then
  override=(--override-input nixpkgs "github:nixos/nixpkgs/$rev" --no-write-lock-file)
fi
ui=$(nix build --no-link --print-out-paths "${override[@]}" .#ui)
UPDATE_CENTER_QML_DIR="$PWD/ui/qml" UPDATE_CENTER_SOCKET=nixos-update-center-dev \
  exec "$ui/bin/nixos-update-center-ui" --show
