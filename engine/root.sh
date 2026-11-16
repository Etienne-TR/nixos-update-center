# @name@-root : les seules actions root du centre de mises à jour, lancées
# par sudo sans mot de passe (règle posée par le module NixOS). Tout vient
# de /etc/@name@/config.json, rien des arguments sauf un numéro.
#   switch                nixos-rebuild switch de la configuration
#   switch-generation N   retour à la génération système N
#   clean                 nh clean all (générations gardées : config.json)
#   boost                 préparation en cours à pleine vitesse

NAME="@name@"
CONFIG="/etc/$NAME/config.json"
cfg() { jq -r "$1 // empty" "$CONFIG"; }

case "${1:-}" in
  switch)
    exec /run/current-system/sw/bin/nixos-rebuild switch --flake "$(cfg .flake)#$(cfg .host)"
    ;;
  switch-generation)
    n="${2:-}"
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "numéro de génération invalide" >&2 && exit 2; }
    [ -e "/nix/var/nix/profiles/system-$n-link" ] || { echo "génération $n introuvable" >&2 && exit 2; }
    /run/current-system/sw/bin/nix-env --profile /nix/var/nix/profiles/system --switch-generation "$n"
    exec /nix/var/nix/profiles/system/bin/switch-to-configuration switch
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
  *)
    echo "usage : $NAME-root switch | switch-generation N | clean | boost" >&2
    exit 2
    ;;
esac
