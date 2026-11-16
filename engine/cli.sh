# @command@ : met à jour le système NixOS, Home Manager et les Flatpaks.
#
# La mise à jour tourne dans l'unité utilisateur @name@-run (lancée ici par
# systemd-run) : fermer le terminal ou Ctrl+C ne l'interrompt pas, et
# l'interface suit la même exécution. Ce script la lance puis affiche son
# journal jusqu'à la fin.

NAME="@name@"
engine="@engine@"
unit="$NAME-run.service"
state="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
run_json="$state/run.json"

usage() {
  cat <<'USAGE'
Usage : @command@ [--system] [--home] [--flatpak] [--all] [--flake]
        @command@ --follow | --stop | --background [parties] | --here [parties]
        @command@ --pending | --news | --boost

  --system      système NixOS (nixos-rebuild switch)
  --home        Home Manager
  --flatpak     Flatpaks (flatpak update, puis retrait des runtimes inutilisés)
  --all         les trois (par défaut)
  --flake       d'abord nix flake update, avec commit de flake.lock s'il
                change ; seul, ne fait que ça

  --follow      suivre la mise à jour en cours
  --stop        arrêter la mise à jour en cours
  --background  lancer sans suivre (l'interface ou --follow la montrent)
  --here        lancer dans ce terminal, sans unité systemd
  --pending     ce qui attend d'être installé
  --news        nouveautés Home Manager du dernier switch qui en avait
  --boost       passer la préparation en arrière-plan à pleine vitesse

Chaque partie demandée est lancée même si une précédente a échoué. Ensuite :
push des commits automatiques si tous les switch ont réussi, nettoyage des
anciennes générations si au moins un a réussi, une notification
récapitulative ; code de sortie 1 si une partie a échoué. La préparation en
arrière-plan (lancée le mercredi) est d'abord arrêtée : ce qu'elle a
construit ou téléchargé sert tel quel.
USAGE
}

parts=() mode=follow
for arg in "$@"; do
  case "$arg" in
    --system | --home | --flatpak | --all | --flake) parts+=("$arg") ;;
    --follow) mode=follow-only ;;
    --stop) mode=stop ;;
    --background) mode=background ;;
    --here) mode=here ;;
    --pending) exec "$engine" pending ;;
    --news) exec "$engine" news ;;
    --boost) exec "$engine" boost ;;
    -h | --help) usage && exit 0 ;;
    *) usage >&2 && exit 2 ;;
  esac
done

active() { systemctl --user is-active --quiet "$unit"; }

# Affiche le journal de l'exécution `id` jusqu'à sa fin, puis son résultat.
follow() {
  local id="$1" log pid
  for _ in $(seq 100); do
    [ "$(jq -r .id "$run_json" 2>/dev/null)" = "$id" ] && break
    sleep 0.1
  done
  log=$(jq -r .log "$run_json")
  pid=$(jq -r .pid "$run_json")
  trap 'printf "\nLa mise à jour continue en arrière-plan : « @command@ --follow » pour la suivre, « @command@ --stop » pour l arrêter.\n"; exit 130' INT
  if kill -0 "$pid" 2>/dev/null; then
    tail -n +1 -F --pid="$pid" "$log" 2>/dev/null
  else
    cat "$log"
  fi
  case "$(jq -r .state "$run_json")" in
    success) exit 0 ;;
    stopped) echo "Mise à jour arrêtée." && exit 130 ;;
    running) echo "Mise à jour interrompue." && exit 1 ;;
    *) exit 1 ;;
  esac
}

case "$mode" in
  stop)
    if active; then
      systemctl --user stop "$unit" && echo "Mise à jour arrêtée."
    else
      echo "Aucune mise à jour en cours."
    fi
    exit 0
    ;;
  follow-only)
    active || { echo "Aucune mise à jour en cours." && exit 0; }
    follow "$(jq -r .id "$run_json")"
    ;;
  here)
    active && { echo "Une mise à jour est déjà en cours : @command@ --follow." >&2 && exit 1; }
    exec "$engine" run "${parts[@]}"
    ;;
esac

if active; then
  [ "$mode" = background ] && exit 0
  echo "Une mise à jour est déjà en cours : je l'affiche (Ctrl+C pour la laisser continuer seule)."
  echo
  follow "$(jq -r .id "$run_json")"
fi

# Environnement de la session transmis à l'unité (PATH avec home-manager,
# agent SSH pour le push, langue).
id=$(date +%Y%m%d-%H%M%S)
env_args=("--setenv=UPDATE_CENTER_RUN_ID=$id")
for v in PATH SSH_AUTH_SOCK LANG LC_ALL LC_MESSAGES WAYLAND_DISPLAY DISPLAY DBUS_SESSION_BUS_ADDRESS NIX_PATH \
  XDG_STATE_HOME XDG_DATA_HOME XDG_CONFIG_HOME UPDATE_CENTER_CONFIG; do
  [ -z "${!v:-}" ] || env_args+=("--setenv=$v=${!v}")
done
[ "$mode" = background ] || [ ! -t 1 ] || env_args+=("--setenv=UPDATE_CENTER_COLOR=1")

mkdir -p "$state"
systemd-run --user --quiet --collect --unit="$unit" --service-type=exec \
  --description="Mise à jour (système, Home Manager, Flatpak)" \
  -p TimeoutStopSec=90 "${env_args[@]}" -- "$engine" run "${parts[@]}" ||
  { echo "Lancement de la mise à jour impossible." >&2 && exit 1; }

[ "$mode" = background ] && exit 0
follow "$id"
