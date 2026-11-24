#!/usr/bin/env bash
# Interface en mode développement, à côté de celle installée :
# - le QML est lu dans ui/qml et la fenêtre rechargée à chaque modification ;
# - le moteur (engine/) et le C++ (ui/src) sont reconstruits dès qu'ils
#   changent, et l'interface relancée avec eux (si la construction échoue,
#   l'ancienne continue et l'erreur va dans le journal).
# « Quitter » dans le menu de l'icône arrête tout. Lancé sans terminal
# (lanceur), sortie dans ~/.local/state/nixos-update-center/dev.log.
set -euo pipefail
cd "$(dirname "$0")/.."
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

# Empreinte de ce qui demande une reconstruction (tout sauf le QML).
sources() {
  find engine ui/src ui/CMakeLists.txt ui/package.nix flake.nix meta.nix -type f -print0 |
    sort -z | xargs -0 sha256sum | sha256sum
}

ui="" engine="" pid=""
build() {
  echo "== $(date +%T) construction"
  ui=$(nix build --no-link --print-out-paths "${override[@]}" .#ui) &&
    engine=$(nix build --no-link --print-out-paths "${override[@]}" .#engine)
}
start() {
  # Messages Qt (erreurs QML comprises) dans ce journal, pas dans journald.
  # Moteur du dépôt aussi (vérifications, et mises à jour lancées depuis
  # cette fenêtre : sa commande passe en tête du PATH).
  PATH="$engine/bin:$PATH" UPDATE_CENTER_ENGINE="$engine/bin/nixos-update-center-engine" \
    UPDATE_CENTER_QML_DIR="$PWD/ui/qml" UPDATE_CENTER_SOCKET=nixos-update-center-dev \
    QT_FORCE_STDERR_LOGGING=1 \
    "$ui/bin/nixos-update-center-ui" --show &
  pid=$!
  echo "== $(date +%T) interface lancée ($pid)"
}

build
start
last=$(sources)
while kill -0 "$pid" 2>/dev/null; do
  sleep 2
  now=$(sources)
  [ "$now" != "$last" ] || continue
  last=$now
  if build; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    start
  else
    echo "== construction en échec : l'interface actuelle continue"
  fi
done
echo "== $(date +%T) interface fermée"
