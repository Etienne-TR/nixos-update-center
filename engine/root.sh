# @name@-root : les seules actions root du centre de mises à jour, lancées
# par sudo sans mot de passe (règle posée par le module NixOS). Tout vient
# de /etc/@name@/config.json ; en argument, seulement un numéro de
# génération ou le chemin d'une génération système déjà construite.
#   switch-to CHEMIN      active une génération système déjà construite
#                         par l'utilisateur (comme nixos-rebuild switch)
#   switch-generation N   retour à la génération système N
#   clean                 nh clean all (générations gardées : config.json)
#   boost                 préparation en cours à pleine vitesse

NAME="@name@"
CONFIG="/etc/$NAME/config.json"
cfg() { jq -r "$1 // empty" "$CONFIG"; }

# Activation dans sa propre unité, comme nixos-rebuild : elle va au bout
# même si la mise à jour qui l'a demandée est arrêtée.
activate() {
  exec /run/current-system/sw/bin/systemd-run --collect --no-ask-password --pipe --quiet \
    --service-type=exec --unit=nixos-rebuild-switch-to-configuration --wait \
    -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER= \
    "$1/bin/switch-to-configuration" switch
}

case "${1:-}" in
  switch-to)
    p="${2:-}"
    [[ "$p" =~ ^/nix/store/[a-z0-9]{32}-nixos-system-[^/]+$ ]] && [ -x "$p/bin/switch-to-configuration" ] ||
      { echo "génération système invalide : $p" >&2 && exit 2; }
    /run/current-system/sw/bin/nix-store --check-validity "$p"
    /run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --set "$p"
    activate "$p"
    ;;
  switch-generation)
    n="${2:-}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "numéro de génération invalide" >&2 && exit 2; }
    [ -e "/nix/var/nix/profiles/system-$n-link" ] || { echo "génération $n introuvable" >&2 && exit 2; }
    /run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --switch-generation "$n"
    activate "$(readlink -f /nix/var/nix/profiles/system)"
    ;;
  clean)
    exec nh clean all --keep "$(cfg .clean.keep)" --keep-since "$(cfg .clean.keepSince)"
    ;;
  boost)
    # Les processus de la préparation (et ceux qu'ils lanceront ensuite,
    # qui héritent de leur priorité) repassent en priorité normale.
    procs="/sys/fs/cgroup/system.slice/$NAME-prebuild.service/cgroup.procs"
    [ -r "$procs" ] || { echo "aucune préparation en cours" >&2 && exit 1; }
    /run/current-system/sw/bin/systemctl set-property --runtime "$NAME-prebuild.service" CPUWeight=100 IOWeight=100
    while read -r pid; do
      chrt --all-tasks --other --pid 0 "$pid" 2>/dev/null || true
      renice -n 0 -p "$pid" >/dev/null 2>&1 || true
      ionice -c 2 -n 4 -p "$pid" 2>/dev/null || true
    done <"$procs"
    touch "/run/$NAME/boosted"
    echo "Préparation à pleine vitesse."
    ;;
  pause | resume)
    # Pause de la construction : gel de son unité (cgroup), compilations
    # comprises (elles tournent dans l'unité, store local, sans le démon).
    /run/current-system/sw/bin/systemctl is-active --quiet "$NAME-prebuild.service" ||
      { echo "aucune préparation en cours" >&2 && exit 1; }
    if [ "$1" = pause ]; then
      /run/current-system/sw/bin/systemctl freeze "$NAME-prebuild.service"
      touch "/run/$NAME/paused"
      echo "Construction en pause."
    else
      /run/current-system/sw/bin/systemctl thaw "$NAME-prebuild.service"
      rm -f "/run/$NAME/paused"
      echo "Construction reprise."
    fi
    ;;
  *)
    echo "usage : $NAME-root switch-to CHEMIN | switch-generation N | clean | boost | pause | resume" >&2
    exit 2
    ;;
esac
