# @name@-engine : moteur du centre de mises à jour.
#
# Sous-commandes (l'utilisateur tape plutôt `@command@`, cf. cli.sh) :
#   run [--system] [--home] [--flatpak] [--all] [--flake]
#       [--rollback-system N] [--rollback-home N]
#                  la mise à jour elle-même ; lancée dans l'unité utilisateur
#                  @name@-run par `@command@` ou par l'interface
#   prebuild       préparation en arrière-plan (root, service système
#                  @name@-prebuild)
#   pending        calcule ce qui attend d'être installé (pending.json)
#   generations    générations système et Home Manager, en JSON
#   check          chercher les mises à jour : nix flake update (commit),
#                  puis préparation en arrière-plan
#   weekly [--manual]
#                  routine hebdomadaire : check, puis notification
#   settings, apply-settings
#                  réglages de la routine (settings.json) : effectifs, appliquer
#   news           nouveautés Home Manager du dernier switch qui en avait
#   boost          préparation en cours : passer à pleine vitesse
#   start-prebuild, stop-prebuild
#                  lancer ou arrêter la préparation (sans reprise au démarrage)
#   open-update, open-journal
#                  mise à jour (interface ou terminal), journal de la
#                  préparation dans un terminal
#
# Configuration : /etc/@name@/config.json, écrit par le module NixOS
# (UPDATE_CENTER_CONFIG pour en donner un autre).
#
# États lus par l'interface, tous en JSON :
#   ~/.local/state/@name@/run.json       exécution en cours ou dernière
#   ~/.local/state/@name@/history.jsonl  une ligne par exécution terminée
#   ~/.local/state/@name@/pending.json   ce qui attend d'être installé
#   ~/.local/state/@name@/runs/*.log     journal de chaque exécution
#   ~/.local/state/@name@/build-status.json  avancement de la construction en cours
#   /run/@name@/status.json              avancement de la préparation (Nix)
#   /run/@name@/flatpak                  running, done ou failed
#   /var/lib/@name@/prebuild.json        résultat de la dernière préparation

NAME="@name@"
TITLE="@title@"
CONFIG="${UPDATE_CENTER_CONFIG:-/etc/$NAME/config.json}"

die() {
  echo "$NAME : $*" >&2
  exit 2
}
[ -r "$CONFIG" ] || die "configuration introuvable ($CONFIG)"

# Réglages de la routine modifiables depuis l'interface, sans rebuild :
# ~/.config/@name@/settings.json, dont seule la clé « routine » est lue (par
# dessus celle de config.json), y compris par la préparation (root).
user_settings() {
  local home="${HOME:-}"
  [ "$(id -u)" -ne 0 ] || home=$(jq -r '.userHome // empty' "$CONFIG")
  if [ "$(id -u)" -ne 0 ] && [ -n "${XDG_CONFIG_HOME:-}" ]; then
    echo "$XDG_CONFIG_HOME/$NAME/settings.json"
  else
    echo "$home/.config/$NAME/settings.json"
  fi
}
settings_file=$(user_settings)
cfg() {
  local s=/dev/null
  [ ! -r "$settings_file" ] || s="$settings_file"
  jq -r --slurpfile u "$s" \
    '(.routine += ((($u[0] // {}).routine // {}) | if type == "object" then . else {} end)) | '"$1"' // empty' \
    "$CONFIG"
}

flake=$(cfg .flake)
host=$(cfg .host)
hmconf=$(cfg .homeConfiguration)
user=$(cfg .user)
pending_file=$(cfg .pendingFile)
root_helper=$(cfg .rootHelper)
prebuild_unit="$NAME-prebuild.service"


runtime_dir="/run/$NAME"
prebuild_status="$runtime_dir/status.json"
prebuild_flatpak="$runtime_dir/flatpak"
prebuild_result="/var/lib/$NAME/prebuild.json"

# Dossiers de l'utilisateur (sans objet pour prebuild, lancé par root).
state="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
data="${XDG_DATA_HOME:-$HOME/.local/share}/$NAME"
run_json="$state/run.json"
history="$state/history.jsonl"
news_installed="$data/hm-news.json"
# Génération d'avant ce module : ancien emplacement.
[ -e "$news_installed" ] || [ ! -e "${XDG_DATA_HOME:-$HOME/.local/share}/update/hm-news.json" ] ||
  news_installed="${XDG_DATA_HOME:-$HOME/.local/share}/update/hm-news.json"
news_last="$state/hm-news-last.json"

notify() { # icône, titre, corps, options en plus
  local icon="$1" title="$2" body="$3"
  shift 3
  notify-send -a "$TITLE" -i "$icon" "$@" "$title" "$body" || true
}

now() { date +%s; }

# Écrit un fichier JSON d'un coup (lecteurs : jamais de fichier à moitié écrit).
write_json() { # chemin ; JSON sur l'entrée standard
  local tmp="$1.tmp.$$"
  cat >"$tmp" && mv -f "$tmp" "$1"
}

# ───────────────────────────── run ─────────────────────────────

# État de l'exécution, réécrit à chaque changement dans run.json.
run_id="" run_state="" run_step="" run_started=0 run_finished="null" run_log=""
run_progress="null"
part_order=()
declare -A part_label=() part_state=()
notes=()

parts_json() {
  local id
  for id in "${part_order[@]}"; do
    printf '%s\t%s\t%s\n' "$id" "${part_label[$id]}" "${part_state[$id]}"
  done | jq -R 'split("\t") | {id: .[0], label: .[1], state: .[2]}' | jq -s .
}

notes_json() {
  printf '%s\n' "${notes[@]}" | jq -R . | jq -s 'map(select(length > 0))'
}

run_record() {
  jq -n --arg id "$run_id" --arg state "$run_state" --arg step "$run_step" \
    --argjson started "$run_started" --argjson finished "$run_finished" \
    --argjson parts "$(parts_json)" --argjson notes "$(notes_json)" \
    --arg log "$run_log" --argjson progress "$run_progress" --argjson pid "$$" \
    '{id: $id, state: $state, step: $step, started: $started,
      finished: $finished, parts: $parts, notes: $notes, log: $log,
      progress: $progress, pid: $pid}'
}

write_run() { run_record | write_json "$run_json"; }

step() { # étape affichée par l'interface
  run_step="$1" run_progress="null"
  write_run
}

bold="" reset="" first_section=1
section() {
  [ -n "$first_section" ] || printf '\n\n'
  first_section=""
  printf '%s=== %s ===%s\n\n' "$bold" "$1" "$reset"
  step "$1"
}

stop_prebuild() {
  rm -f "$pending_file"
  if systemctl is-active --quiet "$prebuild_unit"; then
    echo "Arrêt de la préparation en arrière-plan (ce qu'elle a construit est gardé)."
    systemctl stop "$prebuild_unit" ||
      echo "Arrêt impossible : elle continue en parallèle, en priorité minimale."
    echo
  fi
}

# Chaque partie est une fonction appelée dans un `if` : set -e n'y
# s'applique pas, d'où les `|| return 1` explicites sur chaque étape qui
# doit faire échouer la partie.

# Entrées à faire avancer (--flake-input) ; aucune : toutes.
flake_inputs=()
part_flake() {
  local msg="chore(flake): mise à jour du flake.lock"
  [ "${#flake_inputs[@]}" -eq 0 ] || msg="chore(flake): mise à jour de ${flake_inputs[*]}"
  nix flake update "${flake_inputs[@]}" || return 1
  if ! git diff --quiet -- flake.lock; then
    git commit -q -m "$msg" -- flake.lock || return 1
    echo "flake.lock mis à jour et committé."
  fi
}

# Extra « paquet patché avec repli » : le paquet patché est construit seul
# avant le switch, pour qu'un patch cassé ne bloque pas la mise à jour. En
# cas d'échec, un fichier témoin « <version> <sha256 du patch> » est
# committé ; la configuration le lit et prend alors le paquet d'origine.
# Pas de nouvel essai tant que ni la version ni le patch ne changent.
patched_ko=()
patched_package() { # nom, attribut de pkgs, patch, témoin (relatifs au flake)
  local name="$1" attr="$2" patch="$3" marker="$4" version out sha target
  target="$flake#nixosConfigurations.$host.pkgs.$attr"
  version=$(nix eval --raw "$target.version") || return 1
  out=$(nix eval --raw "$target.outPath") || return 1
  sha=$(sha256sum "$flake/$patch" | cut -d' ' -f1)
  if [ -e "$flake/$marker" ] && [ "$(cat "$flake/$marker")" = "$version $sha" ]; then
    echo "Patch désactivé pour $name $version (cf. $marker) : construction sautée, $name d'origine utilisé."
    patched_ko+=("$name $version")
  elif [ -e "$out" ] && echo "$name patché déjà présent sur le système, rien à compiler." ||
    { echo "Compilation de $name avec son patch…" &&
      nice -n 19 ionice -c 3 nix build --no-link "$target" &&
      echo "$name patché compilé."; }; then
    # Témoin d'une ancienne version qui ne se construisait pas : périmé.
    if [ -e "$flake/$marker" ]; then
      git rm -q -- "$marker" || return 1
      git commit -q -m "chore($name): patch réactivé pour $name $version" -- "$marker" || return 1
    fi
  else
    echo "Le patch ne se construit plus pour $name $version : patch désactivé, $name d'origine utilisé."
    echo "$version $sha" >"$flake/$marker"
    git add -- "$marker" || return 1
    git commit -q -m "chore($name): patch désactivé pour $name $version" -- "$marker" || return 1
    patched_ko+=("$name $version")
  fi
}

# nix build avec avancement dans un fichier JSON (lu par l'interface) ; le
# journal garde les constructions lancées et les erreurs. Affiche les chemins
# construits.
build_with_progress() { # fichier d'avancement, installables…
  local status="$1" out rc=0
  shift
  out=$(mktemp)
  nix build --no-link --print-out-paths --log-format internal-json -v "$@" \
    2>&1 >"$out" | "$NAME-progress" "$status" >&2 || rc=$?
  cat "$out"
  rm -f "$out" "$status"
  return "$rc"
}

wait_network() {
  echo "Attente du réseau…"
  nm-online -q -t 60 2>/dev/null || true
  for _ in $(seq 30); do
    getent hosts github.com >/dev/null && break
    sleep 1
  done
}

# Rien à installer ? Comparaison du chemin évalué (sans rien construire,
# quelques secondes) avec la génération active. Code 0 si identiques.
unchanged() { # installable, génération active
  local out
  out=$(nix eval --raw "$1.outPath" 2>/dev/null) || return 1
  [ -e "$2" ] && [ "$(readlink -f "$2")" = "$out" ]
}

# Comme unchanged, en JSON : true (à appliquer), false, null (évaluation
# en échec).
differs() { # installable, génération active, fichier où écrire le chemin évalué
  local out err
  err=$(mktemp)
  if ! out=$(nix eval --raw "$1.outPath" 2>"$err"); then
    # Dernière ligne d'erreur de Nix, gardée pour l'interface.
    grep -v '^\s*$' "$err" | tail -n 1 >>"$state/pending-errors.tmp" || true
    rm -f "$err"
    echo null
    return
  fi
  rm -f "$err"
  [ -z "${3:-}" ] || echo "$out" >"$3"
  if [ -e "$2" ] && [ "$(readlink -f "$2")" = "$out" ]; then echo false; else echo true; fi
}

# Paquets qui changent entre deux générations, en JSON :
# [{name, change}] d'après les lignes « [U.] #1 nom 1.0 -> 1.1 » de nvd.
packages_diff() { # génération active, génération construite
  nvd --color never diff "$1" "$2" 2>/dev/null |
    sed -nE 's/^\[([A-Z.]+)\][[:space:]]+#[0-9]+[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/\1\t\2\t\3/p' |
    jq -R 'split("\t") | {kind: .[0], name: .[1], change: (.[2] | gsub(" -> "; " → "))}' | jq -s .
}

# Au moins un switch fait (nettoyage des générations ensuite).
switched=""

part_system() {
  local rc=0 name attr patch marker
  step "Évaluation du système"
  if unchanged "$flake#nixosConfigurations.$host.config.system.build.toplevel" /run/current-system; then
    echo "Système déjà à jour : rien à construire ni à activer."
    notes+=("Système déjà à jour")
    cp -f "$flake/flake.lock" "$state/installed-system.lock"
    git rev-parse HEAD >"$state/installed-system.rev"
    return 0
  fi
  # Un extra ne bloque jamais la mise à jour.
  while IFS=$'\t' read -r -u 3 name attr patch marker; do
    [ -n "$name" ] || continue
    step "Construction de $name patché"
    patched_package "$name" "$attr" "$patch" "$marker" ||
      echo "Préparation de $name patché impossible, switch tenté quand même."
  done 3< <(jq -r '.extras.patchedPackages[]? | [.name, .attr, .patch, .marker] | @tsv' "$CONFIG")
  # Évaluation et construction par l'utilisateur (via nix-daemon, qui sait
  # récupérer toutes les entrées du flake, même privées) ; root ne fait
  # qu'activer la génération construite.
  step "Construction du système"
  echo "Construction du système…"
  local sys
  sys=$(build_with_progress "$state/build-status.json" \
    "$flake#nixosConfigurations.$host.config.system.build.toplevel") || return 1
  step "Switch du système"
  echo "Activation de $sys…"
  sudo "$root_helper" switch-to "$sys" || rc=1
  switched=1
  # Le switch, même raté, peut avoir redémarré NetworkManager et
  # systemd-resolved : retour du réseau et du DNS avant la suite.
  wait_network
  if [ "$rc" -eq 0 ]; then
    cp -f "$flake/flake.lock" "$state/installed-system.lock"
    git rev-parse HEAD >"$state/installed-system.rev"
  fi
  return "$rc"
}

# Extra Voxtype : modèles de dictée téléchargés ici, avec avancement, plutôt
# que par le service voxtype-model-loader pendant le switch.
voxtype_models() {
  local hm="$flake#homeConfigurations.$hmconf.config.services.voxtype" models vox tmp m dir pid bytes
  # shellcheck disable=SC2016 # expression Nix, pas du shell
  models=$(nix eval --raw "$hm.settings" --apply 's: s.${s.engine or "whisper"}.model or ""' 2>/dev/null) || return 0
  [ -n "$models" ] || return 0
  vox=$(nix build --no-link --print-out-paths "$hm.package") || return 0
  # Config temporaire : setup crée un config.toml, qui ne doit pas remplacer
  # celui géré par Home Manager.
  tmp=$(mktemp -d)
  for m in $models; do
    if XDG_CONFIG_HOME="$tmp" "$vox/bin/voxtype" info models --json 2>/dev/null |
      jq -e --arg m "$m" '[.engines[].models[] | select(.download_arg == $m or .name == $m) | .installed] | any' >/dev/null; then
      continue
    fi
    section "Téléchargement du modèle de dictée $m"
    dir="${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models/$m"
    XDG_CONFIG_HOME="$tmp" "$vox/bin/voxtype" setup --download --model "$m" --no-post-install &
    pid=$!
    # Avancement pour l'interface : taille déjà téléchargée.
    while kill -0 "$pid" 2>/dev/null; do
      bytes=$(du -sb "$dir" 2>/dev/null | cut -f1) || true
      run_progress=$(jq -n --arg label "Modèle $m" --argjson bytes "${bytes:-0}" \
        '{label: $label, bytes: $bytes}')
      write_run
      sleep 2
    done
    wait "$pid" || echo "Téléchargement du modèle Voxtype $m en échec (le service réessaiera)."
    run_progress="null"
  done
  rm -rf "$tmp"
}

# Extra Claude Desktop : version publiée plus récente que celle de la
# configuration ? (index apt d'Anthropic). Sortie : « config publiée sha256 ».
claude_index="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"
claude_check() {
  local file index latest sha current
  file="$flake/$(cfg .extras.claudeDesktop.packageFile)"
  current=$(awk -F'"' '/^  version = / { print $2; exit }' "$file")
  index=$(curl -fsS --max-time 20 --retry 3 --retry-delay 5 --retry-all-errors \
    -H 'Cache-Control: no-cache' "$claude_index?t=$(now)") || return 2
  latest=$(awk '/^Version:/ { print $2 }' <<<"$index" | sort -V | tail -n 1)
  sha=$(awk -v v="$latest" '/^Version:/ { ok = ($2 == v) } ok && /^SHA256:/ { print $2; exit }' <<<"$index")
  [ -n "$latest" ] && [ -n "$sha" ] && [ -n "$current" ] || return 2
  echo "$current $latest $sha"
  [ "$latest" != "$current" ] &&
    [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)" = "$latest" ]
}

claude_update() {
  local out rc=0 current latest sha file
  out=$(claude_check) || rc=$?
  read -r current latest sha <<<"$out"
  case "$rc" in
    0) ;;
    1) echo "Claude Desktop à jour ($current)." && return 0 ;;
    *) echo "Vérification de Claude Desktop impossible." && return 1 ;;
  esac
  file=$(cfg .extras.claudeDesktop.packageFile)
  sed -i \
    -e "s/^  version = \"$current\";/  version = \"$latest\";/" \
    -e "s/sha256 = \"[0-9a-f]\{64\}\";/sha256 = \"$sha\";/" \
    "$flake/$file" || return 1
  git commit -q -m "chore(claude-desktop): $current -> $latest" -- "$file" || return 1
  echo "Claude Desktop $current -> $latest : écrit dans la configuration et committé."
  notes+=("Claude Desktop $latest : relancer l'app")
}

news_count=0
part_home() {
  local old_ids new
  find "$HOME/.config" -name "*.home-manager-backup" -type f -delete 2>/dev/null || true
  find "$HOME" -maxdepth 1 -name "*.home-manager-backup" -type f -delete
  if [ "$(cfg .extras.claudeDesktop.enable)" = true ]; then
    step "Vérification de Claude Desktop"
    claude_update || echo "Claude Desktop : en échec, switch fait quand même."
  fi
  old_ids=$(jq -r '.entries[].id' "$news_installed" 2>/dev/null || true)
  [ "$(cfg .extras.voxtype)" != true ] || voxtype_models
  step "Évaluation de Home Manager"
  if unchanged "$flake#homeConfigurations.$hmconf.activationPackage" \
    "$HOME/.local/state/nix/profiles/home-manager"; then
    echo "Home Manager déjà à jour : rien à construire ni à activer."
    notes+=("Home Manager déjà à jour")
    cp -f "$flake/flake.lock" "$state/installed-home.lock"
    git rev-parse HEAD >"$state/installed-home.rev"
    return 0
  fi
  step "Construction de Home Manager"
  build_with_progress "$state/build-status.json" \
    "$flake#homeConfigurations.$hmconf.activationPackage" >/dev/null || return 1
  step "Switch de Home Manager"
  switched=1
  home-manager switch -b home-manager-backup --flake "$flake#$hmconf" || return 1
  cp -f "$flake/flake.lock" "$state/installed-home.lock"
  git rev-parse HEAD >"$state/installed-home.rev"
  # Nouveautés Home Manager : ids de la génération d'avant comparés à ceux
  # de la nouvelle ; les nouvelles (pertinentes) sont gardées pour `news`.
  if [ -n "$old_ids" ] && [ -e "$news_installed" ]; then
    new=$(jq --arg old "$old_ids" --arg date "$(date '+%d/%m/%Y %H:%M')" --argjson time "$(now)" '
      ($old | split("\n")) as $o
      | { date: $date, time: $time,
          entries: [.entries[] | select(.condition) | select(.id as $i | $o | index($i) | not)] }
    ' "$news_installed") || return 0
    news_count=$(jq '.entries | length' <<<"$new")
    [ "$news_count" -eq 0 ] || printf '%s\n' "$new" >"$news_last"
  fi
}

part_flatpak() {
  flatpak update --user -y --noninteractive || return 1
  # Sans le bloc « These runtimes … are pinned and won't be removed »
  # répété à chaque fois. pipefail garde l'échec de flatpak.
  flatpak uninstall --user --unused -y --noninteractive 2>&1 |
    awk '/^These runtimes in installation .* are pinned/ { skip = 1; next }
         skip && (/^[[:space:]]/ || /^$/) { next }
         { skip = 0; print }' || return 1
}

rollback_system_gen="" rollback_home_gen=""
part_rollback_system() {
  sudo "$root_helper" switch-generation "$rollback_system_gen" || return 1
  wait_network
}

part_rollback_home() {
  local link="$HOME/.local/state/nix/profiles/home-manager-$rollback_home_gen-link"
  [ -e "$link/activate" ] || { echo "Génération Home Manager $rollback_home_gen introuvable." && return 1; }
  "$link/activate"
}

cmd_run() {
  local system="" home="" flatpak="" flake_update=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --system) system=1 ;;
      --home) home=1 ;;
      --flatpak) flatpak=1 ;;
      --all) system=1 home=1 flatpak=1 ;;
      --flake) flake_update=1 ;;
      --flake-input)
        [[ "${2:-}" =~ ^[A-Za-z0-9_-]+$ ]] || die "nom d'entrée invalide : ${2:-}"
        flake_update=1 flake_inputs+=("$2")
        shift
        ;;
      --rollback-system) rollback_system_gen="${2:?}" && shift ;;
      --rollback-home) rollback_home_gen="${2:?}" && shift ;;
      *) die "option inconnue : $1" ;;
    esac
    shift
  done
  if [ -z "$system$home$flatpak$flake_update$rollback_system_gen$rollback_home_gen" ]; then
    system=1 home=1
    [ "$(cfg .flatpak)" != true ] || flatpak=1
  fi
  [ "$(cfg .flatpak)" = true ] || flatpak=""

  mkdir -p "$state/runs"
  run_id="${UPDATE_CENTER_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
  run_log="$state/runs/$run_id.log"
  run_started=$(now) run_state=running
  if [ -n "${UPDATE_CENTER_COLOR:-}" ] || [ -t 1 ]; then bold=$'\e[1m' reset=$'\e[0m'; fi
  # Journal de l'exécution dans un fichier (suivi par `@command@` et
  # l'interface) en plus de la sortie (journal de l'unité).
  exec > >(tee -a "$run_log") 2>&1
  # Garder les 30 derniers journaux.
  find "$state/runs" -name '*.log' -printf '%T@ %p\n' | sort -rn | tail -n +31 | cut -d' ' -f2- |
    xargs -r rm -f

  add_part() {
    part_order+=("$1")
    part_label[$1]="$2"
    part_state[$1]=pending
  }
  if [ -n "$flake_update" ]; then
    if [ "${#flake_inputs[@]}" -gt 0 ]; then add_part flake "Flake (${flake_inputs[*]})"; else add_part flake "Flake"; fi
  fi
  [ -z "$rollback_system_gen" ] || add_part rollback_system "Retour à la génération système $rollback_system_gen"
  [ -z "$rollback_home_gen" ] || add_part rollback_home "Retour à la génération Home Manager $rollback_home_gen"
  [ -z "$system" ] || add_part system "Système"
  [ -z "$home" ] || add_part home "Home Manager"
  [ -z "$flatpak" ] || add_part flatpak "Flatpak"
  write_run

  # Arrêt demandé (`@command@ --stop`, interface) : noté avant de sortir.
  trap 'run_state=stopped run_finished=$(now); write_run; run_record | jq -c . >>"$history"; exit 143' TERM

  cd "$flake"
  [ -z "$system$home$flatpak$rollback_system_gen$rollback_home_gen" ] || stop_prebuild

  local failed="" switch_ok="" switch_ko="" id
  declare -A titles=(
    [flake]="Mise à jour du flake (nix flake update)"
    [system]="Mise à jour du système NixOS"
    [home]="Mise à jour de Home Manager"
    [flatpak]="Mise à jour des Flatpaks"
    [rollback_system]="Retour à une génération système précédente"
    [rollback_home]="Retour à une génération Home Manager précédente"
  )
  for id in "${part_order[@]}"; do
    section "${titles[$id]}"
    part_state[$id]=running
    write_run
    if "part_$id"; then
      part_state[$id]=success
      case "$id" in system | home) switch_ok=1 ;; esac
    else
      echo "*** ${part_label[$id]} : échec ***" >&2
      part_state[$id]=failed
      failed=1
      case "$id" in system | home) switch_ko=1 ;; esac
    fi
    write_run
  done

  # Push des commits automatiques seulement si tous les switch ont réussi :
  # un flake.lock qui casse un switch n'est pas publié.
  local pending push_note=""
  if [ -n "$system$home" ] && [ "$(cfg .push)" = true ]; then
    section "Envoi des commits"
    pending=$(git log --oneline '@{u}..' 2>/dev/null || true)
    if [ -z "$pending" ]; then
      echo "Rien à envoyer."
    elif [ -z "$switch_ko" ]; then
      echo "$pending"
      if git push -q; then
        echo "Envoyés."
      else
        push_note="push en échec : voir le journal"
        failed=1
      fi
    else
      echo "$pending"
      push_note="push reporté : voir le journal"
      echo "Non envoyés (un switch a échoué) : ils partiront au prochain update réussi."
    fi
  fi

  # Seul nettoyage des anciennes générations, si au moins un switch a réussi.
  if [ -n "$switch_ok" ] && [ -n "$switched" ] && [ "$(cfg .clean.enable)" = true ]; then
    printf '\n\n%s=== %s ===%s\n' "$bold" "Nettoyage des anciennes générations" "$reset"
    step "Nettoyage des anciennes générations"
    sudo "$root_helper" clean || echo "Nettoyage en échec."
  fi

  [ "$news_count" -eq 0 ] || notes+=("$news_count nouveauté(s) Home Manager : @command@ --news")
  for id in "${patched_ko[@]}"; do notes+=("⚠ patch désactivé ($id)"); done
  [ -z "$push_note" ] || notes+=("$push_note")

  local ok_count=0 lines=() title
  for id in "${part_order[@]}"; do
    if [ "${part_state[$id]}" = success ]; then
      lines+=("✓ ${part_label[$id]}")
      ok_count=$((ok_count + 1))
    else
      lines+=("✗ ${part_label[$id]}")
    fi
  done
  lines+=("${notes[@]}")
  run_finished=$(now) run_step=""
  if [ -z "$failed" ]; then
    run_state=success
  elif [ "$ok_count" -gt 0 ]; then
    run_state=partial
  else
    run_state=failed
  fi
  write_run
  run_record | jq -c . >>"$history"

  # Une seule notification récapitulative, persistante en cas d'échec (sauf
  # pour une mise à jour du flake seule, faite par la routine).
  if [ "${#part_order[@]}" -gt 0 ] && [ "${part_order[*]}" != flake ]; then
    local body
    body=$(printf '%s\n' "${lines[@]}")
    case "$run_state" in
      success) notify object-select-symbolic "Mise à jour terminée" "$body" ;;
      partial) notify dialog-error-symbolic "Mise à jour incomplète" "$body" -t 0 ;;
      *) notify dialog-error-symbolic "Mise à jour en échec" "$body" -t 0 ;;
    esac
  fi
  if [ -z "$failed" ]; then
    printf '\nTerminé.\n'
  else
    printf '\nTerminé avec des erreurs.\n'
    exit 1
  fi
}

# ─────────────────────────── prebuild ───────────────────────────

# Service système, exécuté par root sur le store local : les constructions
# héritent de sa priorité minimale. Construit sans activer la génération
# système et la génération Home Manager et, en parallèle, télécharge les
# Flatpaks de l'utilisateur sans les déployer.
cmd_prebuild() {
  local home rc=0 flatpak_pid="" paths
  home=$(cfg .userHome)
  finish() { # état, chemins construits (JSON)
    jq -n --arg state "$1" --argjson time "$(now)" --argjson paths "${2:-null}" \
      '{state: $state, time: $time, paths: $paths}' | write_json "$prebuild_result"
  }
  trap 'finish stopped; exit 0' TERM

  as_user() {
    setpriv --reuid="$user" --regid="$(id -g "$user")" --init-groups -- \
      env HOME="$home" XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" "$@"
  }

  if [ "$(cfg .routine.flatpak)" = true ]; then
    echo running >"$prebuild_flatpak"
    (
      if as_user flatpak update --user --no-deploy -y --noninteractive; then
        echo "Flatpaks téléchargés."
        echo "done" >"$prebuild_flatpak.tmp"
      else
        echo "Téléchargement des Flatpaks en échec."
        echo failed >"$prebuild_flatpak.tmp"
      fi
      mv "$prebuild_flatpak.tmp" "$prebuild_flatpak"
    ) &
    flatpak_pid=$!
  fi

  cd "$flake"
  echo "Préparation de $host et de Home Manager (construction seule, rien n'est activé)."
  jq -n --argjson t "$(now)" '{phase: "eval", builds: {}, downloads: {}, building: [],
    substituting: [], started: $t, updated: $t}' | write_json "$prebuild_status"
  # Évaluation par l'utilisateur, via nix-daemon : root ne saurait pas
  # récupérer une entrée privée du flake (pas de clé SSH). Les .drv obtenus
  # sont ensuite construits ici, sur le store local, en priorité minimale.
  local drvs sys_drv home_drv
  if drvs=$(as_user env -u NIX_REMOTE nix path-info --derivation \
    "$flake#nixosConfigurations.$host.config.system.build.toplevel" \
    "$flake#homeConfigurations.$hmconf.activationPackage"); then
    sys_drv=$(grep -- '-nixos-system-' <<<"$drvs" | head -n 1 || true)
    home_drv=$(grep -- '-home-manager-generation' <<<"$drvs" | head -n 1 || true)
  else
    echo "Évaluation de la configuration en échec."
    rc=1
  fi
  paths=$(mktemp)
  if [ -n "${sys_drv:-}" ] && [ -n "${home_drv:-}" ]; then
    # --keep-going : un paquet en échec (patch cassé…) n'empêche pas de
    # construire le reste ; la mise à jour s'en occupera.
    nix build --no-link --print-out-paths --keep-going --log-format internal-json -v \
      "$sys_drv^*" "$home_drv^*" \
      2>&1 >"$paths" | "$NAME-progress" "$prebuild_status" || rc=$?
  else
    rc=1
  fi

  if [ -n "$flatpak_pid" ]; then
    wait "$flatpak_pid" || true
    [ "$(cat "$prebuild_flatpak")" = "done" ] || rc=1
  fi

  rm -f "$pending_file"
  local built
  built=$(jq -R . "$paths" | jq -s 'if length == 2 then
    {system: (map(select(test("-nixos-system-"))) | .[0]),
     home: (map(select(test("-home-manager-generation"))) | .[0])} else null end')
  rm -f "$paths"
  if [ "$rc" -eq 0 ]; then
    echo "Préparation terminée : la mise à jour n'aura presque plus qu'à activer."
    finish success "$built"
  else
    echo "Préparation incomplète (code $rc) : la mise à jour reprendra ce qui manque."
    finish failed "$built"
  fi
  # Ce qui attend d'être installé, pour l'interface.
  as_user "$0" pending >/dev/null || echo "Calcul de ce qui est en attente impossible."
  rm -f "$prebuild_status"
  [ "$rc" -eq 0 ] || exit "$rc"
}

cmd_boost() {
  systemctl is-active --quiet "$prebuild_unit" || die "aucune préparation en cours"
  sudo "$root_helper" boost
}

# ─────────────────────────── pending ───────────────────────────

# Entrées du flake qui diffèrent entre deux flake.lock (JSON).
lock_diff_raw() { # ancien, nouveau
  jq -n --slurpfile a "$1" --slurpfile b "$2" '
    ($a[0]) as $A | ($b[0]) as $B
    | [ $B.nodes.root.inputs | to_entries[] | select(.value | type == "string")
        | .key as $name
        | ($A.nodes.root.inputs[$name] // null) as $an
        | { name: $name,
            from: (if ($an | type) == "string" then $A.nodes[$an].locked else null end),
            to: $B.nodes[.value].locked }
        | select((.from.rev // .from.narHash // null) != (.to.rev // .to.narHash))
        | { name,
            from: (if .from then {rev: (.from.rev // null), date: (.from.lastModified // null)} else null end),
            to: {rev: (.to.rev // null), date: (.to.lastModified // null),
                 owner: (.to.owner // null), repo: (.to.repo // null), type: (.to.type // null),
                 url: (.to.url // null)} } ]'
}

# Entrées du flake changées, avec ce qui parle plus qu'un commit : version du
# paquet principal de l'entrée (packages.<système>.default.version), ou à
# défaut lib.version (version de distribution de nixpkgs), aux deux commits,
# et nombre de commits entre les deux (GitHub).
# Résultats gardés dans input-cache.json (un commit ne change pas).
lock_diff() { # ancien, nouveau
  local json n i type owner repo url from to sys cache fv tv commits
  json=$(lock_diff_raw "$1" "$2")
  n=$(jq length <<<"$json")
  [ "$n" -gt 0 ] || { echo "$json" && return; }
  cache="$state/input-cache.json"
  [ -s "$cache" ] || echo '{}' >"$cache"
  sys=$(uname -m)-linux
  ref() { # commit → référence de flake
    case "$type" in
      github) echo "github:$owner/$repo/$1" ;;
      git) echo "git+$url?rev=$1" ;;
    esac
  }
  version() { # commit → version (vide si aucune)
    local r key v
    r=$(ref "$1")
    [ -n "$r" ] && [ "$1" != - ] || return 0
    key="v2:$r"
    if v=$(jq -er --arg k "$key" '.[$k] // empty' "$cache" 2>/dev/null); then
      echo "$v"
      return 0
    fi
    # Vérification rapide : seulement ce qui est déjà en cache.
    [ -z "${pending_quick:-}" ] || return 0
    v=$(timeout 120 nix eval --raw "$r#packages.$sys.default.version" 2>/dev/null || true)
    # Sans paquet principal (nixpkgs) : version de la distribution, par
    # exemple 26.11.20261116.1c872b8.
    [ -n "$v" ] || v=$(timeout 120 nix eval --raw "$r#lib.version" 2>/dev/null || true)
    jq --arg k "$key" --arg v "$v" '.[$k] = $v' "$cache" | write_json "$cache"
    echo "$v"
  }
  for ((i = 0; i < n; i++)); do
    IFS=$'\t' read -r type owner repo url from to < <(jq -r --argjson i "$i" \
      '.[$i] | [.to.type // "-", .to.owner // "-", .to.repo // "-", .to.url // "-", .from.rev // "-", .to.rev // "-"] | @tsv' <<<"$json")
    fv=$(version "$from")
    tv=$(version "$to")
    commits=null
    if [ "$type" = github ] && [ "$from" != - ] && [ "$to" != - ]; then
      local key="c:$owner/$repo/$from...$to"
      if ! commits=$(jq -e --arg k "$key" '.[$k]' "$cache" 2>/dev/null) && [ -n "${pending_quick:-}" ]; then
        commits=null
      elif [ "$commits" = "" ] || [ "$commits" = null ]; then
        commits=$(curl -fsS --max-time 10 "https://api.github.com/repos/$owner/$repo/compare/$from...$to" 2>/dev/null |
          jq '.ahead_by // null' 2>/dev/null || echo null)
        [ -n "$commits" ] || commits=null
        [ "$commits" = null ] || jq --arg k "$key" --argjson c "$commits" '.[$k] = $c' "$cache" | write_json "$cache"
      fi
    fi
    json=$(jq --argjson i "$i" --arg fv "$fv" --arg tv "$tv" --argjson c "$commits" \
      '.[$i] += {fromVersion: (if $fv == "" then null else $fv end), toVersion: (if $tv == "" then null else $tv end), commits: $c}' <<<"$json")
  done
  echo "$json"
}

# Changements depuis la dernière application d'une partie (system, home ou
# flake pour flake.nix),
# en JSON : {commits: [{hash, subject}], dirty: ["M chemin"], inputs: […]}.
# commits et dirty : modifications de la config (sans flake.lock) ; inputs :
# entrées du flake.lock pas encore installées pour cette partie.
changes() { # partie, dépôt, flake.lock relatif au dépôt, flake relatif, flake.lock, tmp
  local part="$1" repo="$2" rel="$3" dir="$4" cur="$5" tmp="$6" rev lock prefixes base="$1"
  # « flake » : modifications de flake.nix, depuis la dernière application
  # du système.
  [ "$part" != flake ] || base=system
  prefixes=$(jq -c --arg p "$part" '.paths[$p] // []' "$CONFIG")
  # Fichier (relatif au flake) concerné par cette partie : dans un de ses
  # dossiers, ou hors des dossiers de toutes les parties.
  # shellcheck disable=SC2016 # expression jq
  # flake.lock et flake.nix à part (section du flake) : versions et entrées
  # du flake, pas modification de la config du système ou de Home Manager.
  local relevant='(. != "flake.lock") and (. != "flake.nix") and ((. as $f | ($own | any(. as $d | $f | startswith($d + "/"))))
    or (. as $f | ($all | any(. as $d | $f | startswith($d + "/"))) | not))'
  # shellcheck disable=SC2016 # expression jq
  [ "$part" != flake ] || relevant='(. == "flake.nix")'
  lock="$state/installed-$base.lock"
  if [ ! -e "$lock" ]; then
    lock="$tmp/base-$base.lock"
    git -C "$repo" show "@{u}:$rel" >"$lock" 2>/dev/null || cp "$cur" "$lock"
  fi
  rev=$(cat "$state/installed-$base.rev" 2>/dev/null || git -C "$repo" rev-parse '@{u}' 2>/dev/null || true)
  local all
  all=$(jq -c '[.paths[]?[]]' "$CONFIG")
  {
    if [ -n "$rev" ]; then
      git -C "$repo" log --format='@@%h%x09%s' --name-only --relative="$dir" "$rev..HEAD" -- "$dir" 2>/dev/null || true
    fi
  } | jq -R -s --argjson own "$prefixes" --argjson all "$all" '
      split("\n@@") | map(ltrimstr("@@") | select(length > 0) | split("\n") | map(select(length > 0)))
      | map({hash: (.[0] | split("\t")[0]), subject: (.[0] | split("\t")[1:] | join("\t")),
             files: .[1:]})
      | map(select(.files | any('"$relevant"')))
      | map(del(.files))' >"$tmp/commits-$part"
  git -C "$repo" status --porcelain -- "$dir" 2>/dev/null |
    jq -R -s --argjson own "$prefixes" --argjson all "$all" --arg dir "$dir/" '
      split("\n") | map(select(length > 0))
      | map({st: .[0:2], path: (.[3:] | ltrimstr($dir))})
      | map(select(.path | '"$relevant"') | "\(.st) \(.path)")' >"$tmp/dirty-$part"
  jq -n --slurpfile c "$tmp/commits-$part" --slurpfile d "$tmp/dirty-$part" \
    --argjson inputs "$(lock_diff "$lock" "$cur")" \
    '{commits: $c[0], dirty: $d[0], inputs: $inputs}'
}

# Ce qui attend, en trois tests séparés :
# - config système à appliquer : le système évalué diffère de la génération
#   active (changement de la config ou du flake.lock déjà committé) ;
# - config Home Manager à appliquer : idem pour Home Manager ;
# - nouvelles versions proposées par le flake : nix flake update à blanc
#   (--output-lock-file, flake.lock inchangé).
# Plus le détail : commits et fichiers modifiés depuis la dernière
# application, entrées du flake.lock changées, paquets qui changent (nvd, si
# la préparation a construit), Flatpaks, Claude Desktop, commits non envoyés.
# Écrit pending.json et l'affiche.
# --quick : seulement git et les fichiers locaux (moins d'une seconde) :
# commits, fichiers modifiés et entrées du flake.lock depuis la dernière
# application ; « à appliquer » déduit de git, sans évaluation. Nouvelles
# versions en ligne, Flatpaks et Claude Desktop : ceux de la dernière
# vérification complète.
pending_quick=""
cmd_pending() {
  [ "${1:-}" != --quick ] || pending_quick=1
  local repo rel dir cur tmp prev
  # Une seule vérification à la fois (deux fenêtres, routine…) : la suivante
  # attend la fin de la première.
  mkdir -p "$state"
  exec 8>"$state/pending.lock"
  flock 8
  rm -f "$state/pending-errors.tmp"
  local sys_changed=null home_changed=null upstream="[]" upstream_ok=false
  local built_sys built_home
  local flatpaks="[]" claude="null" unpushed="[]" out rc
  mkdir -p "$state"
  tmp=$(mktemp -d)
  repo=$(git -C "$flake" rev-parse --show-toplevel)
  rel=$(realpath --relative-to="$repo" "$flake/flake.lock")
  dir=$(realpath --relative-to="$repo" "$flake")
  cur="$flake/flake.lock"

  prev="$state/pending.json"
  [ -s "$prev" ] || prev=/dev/null
  # 1 et 2 : évaluation seule, comparée aux générations actives.
  # Générations évaluées (target) : reprises de la dernière vérification
  # complète par la rapide, si la config n'a pas bougé depuis (même commit,
  # mêmes fichiers modifiés).
  local head dirty_hash target_sys="" target_home=""
  head=$(git -C "$repo" rev-parse HEAD)
  dirty_hash=$(git -C "$repo" status --porcelain | sha256sum | cut -d' ' -f1)
  if [ -z "$pending_quick" ]; then
    sys_changed=$(differs "$flake#nixosConfigurations.$host.config.system.build.toplevel" /run/current-system "$tmp/target-sys")
    home_changed=$(differs "$flake#homeConfigurations.$hmconf.activationPackage" \
      "$HOME/.local/state/nix/profiles/home-manager" "$tmp/target-home")
    target_sys=$(cat "$tmp/target-sys" 2>/dev/null || true)
    target_home=$(cat "$tmp/target-home" 2>/dev/null || true)
  elif [ "$(jq -r '.head // ""' "$prev")" = "$head" ] && [ "$(jq -r '.dirtyHash // ""' "$prev")" = "$dirty_hash" ]; then
    target_sys=$(jq -r '.apply.system.target // ""' "$prev")
    target_home=$(jq -r '.apply.home.target // ""' "$prev")
  fi

  # Détail de ce qui est à appliquer, pour chaque partie depuis sa dernière
  # application : commits et fichiers modifiés (rangés par dossier :
  # config.json paths.system / paths.home ; ailleurs, comme flake.nix ou
  # flake.lock : les deux), entrées du flake.lock pas encore installées.
  local sys_changes home_changes flake_changes
  sys_changes=$(changes system "$repo" "$rel" "$dir" "$cur" "$tmp")
  home_changes=$(changes home "$repo" "$rel" "$dir" "$cur" "$tmp")
  flake_changes=$(changes flake "$repo" "$rel" "$dir" "$cur" "$tmp")

  # Paquets qui changent : seulement si la préparation a construit
  # exactement la génération de la config actuelle (sinon la liste serait
  # périmée, voire à l'envers).
  local pkgs_sys="[]" pkgs_home="[]"
  built_sys=$(jq -r '.paths.system // empty' "$prebuild_result" 2>/dev/null || true)
  built_home=$(jq -r '.paths.home // empty' "$prebuild_result" 2>/dev/null || true)
  if [ -n "$built_sys" ] && [ "$built_sys" = "$target_sys" ] && [ -e "$built_sys" ] &&
    [ "$(readlink -f /run/current-system)" != "$built_sys" ]; then
    pkgs_sys=$(packages_diff /run/current-system "$built_sys")
  fi
  local hm_profile="$HOME/.local/state/nix/profiles/home-manager"
  if [ -n "$built_home" ] && [ "$built_home" = "$target_home" ] && [ -e "$built_home" ] &&
    [ -e "$hm_profile" ] && [ "$(readlink -f "$hm_profile")" != "$built_home" ]; then
    pkgs_home=$(packages_diff "$hm_profile" "$built_home")
  fi

  if [ -n "$pending_quick" ]; then
    # Déduit de git : quelque chose depuis la dernière application ?
    local fl
    fl=$(jq '(.commits | length) + (.dirty | length)' <<<"$flake_changes")
    sys_changed=$(jq --argjson f "$fl" '(.commits | length) + (.dirty | length) + (.inputs | length) + $f > 0' <<<"$sys_changes")
    home_changed=$(jq --argjson f "$fl" '(.commits | length) + (.dirty | length) + (.inputs | length) + $f > 0' <<<"$home_changes")
    # Sans celles que flake.lock a rattrapées depuis (entrée mise à jour seule).
    upstream=$(jq -c --slurpfile l "$cur" '($l[0]) as $L
      | [.upstream.inputs[]? | select(.to.rev != ($L.nodes[$L.nodes.root.inputs[.name] // ""].locked.rev // ""))]' \
      "$prev" 2>/dev/null || echo "[]")
    upstream_ok=$(jq -c '.upstream.checked // false' "$prev" 2>/dev/null || echo false)
    flatpaks=$(jq -c '.flatpaks // []' "$prev" 2>/dev/null || echo "[]")
    claude=$(jq -c '.claudeDesktop // null' "$prev" 2>/dev/null || echo null)
  fi

  # 3 : nouvelles versions proposées par le flake, sans toucher flake.lock.
  if [ -z "$pending_quick" ] && (cd "$flake" && nix flake update --output-lock-file "$tmp/new.lock" >/dev/null 2>&1); then
    upstream=$(lock_diff "$cur" "$tmp/new.lock")
    upstream_ok=true
  fi

  if [ -z "$pending_quick" ] && [ "$(cfg .flatpak)" = true ]; then
    flatpaks=$(flatpak remote-ls --updates --user --columns=application,name,branch 2>/dev/null |
      jq -R 'split("\t") | select(length >= 3) | {id: .[0], name: .[1], branch: .[2]}' | jq -s .)
  fi

  if [ -z "$pending_quick" ] && [ "$(cfg .extras.claudeDesktop.enable)" = true ]; then
    rc=0
    out=$(claude_check) || rc=$?
    if [ "$rc" -le 1 ]; then
      read -r c_cur c_latest _ <<<"$out"
      claude=$(jq -n --arg c "$c_cur" --arg l "$c_latest" --argjson a "$([ "$rc" -eq 0 ] && echo true || echo false)" \
        '{configured: $c, latest: $l, available: $a}')
    fi
  fi

  unpushed=$(git -C "$repo" log --format='%h%x09%s' '@{u}..' 2>/dev/null |
    jq -R 'split("\t") | {hash: .[0], subject: .[1]}' | jq -s .)

  local full_time
  full_time=$(now)
  [ -z "$pending_quick" ] || full_time=$(jq '.time // 0' "$prev" 2>/dev/null || echo 0)
  jq -n --argjson time "$full_time" --argjson quickTime "$(now)" \
    --argjson quick "$([ -n "$pending_quick" ] && echo true || echo false)" \
    --argjson sysc "$sys_changed" --argjson homec "$home_changed" \
    --argjson sysch "$sys_changes" --argjson homech "$home_changes" --argjson flakech "$flake_changes" \
    --argjson pkgsys "$pkgs_sys" --argjson pkghome "$pkgs_home" \
    --arg tsys "$target_sys" --arg thome "$target_home" --arg head "$head" --arg dirty "$dirty_hash" \
    --arg sysb "$built_sys" --arg homeb "$built_home" \
    --argjson upstream "$upstream" --argjson upok "$upstream_ok" \
    --argjson flatpaks "$flatpaks" --argjson claude "$claude" --argjson unpushed "$unpushed" \
    --argjson errors "$(jq -R . "$state/pending-errors.tmp" 2>/dev/null | jq -s .)" '
    { time: $time, quickTime: $quickTime, quick: $quick, head: $head, dirtyHash: $dirty,
      apply: {
        system: ({changed: $sysc, built: ($sysb != ""), target: $tsys, packages: $pkgsys} + $sysch),
        home: ({changed: $homec, built: ($homeb != ""), target: $thome, packages: $pkghome} + $homech),
        flake: ($flakech | {commits, dirty}) },
      upstream: {checked: $upok, inputs: $upstream},
      flatpaks: $flatpaks, claudeDesktop: $claude, unpushed: $unpushed,
      errors: $errors }' |
    tee "$state/pending.json.tmp"
  mv -f "$state/pending.json.tmp" "$state/pending.json"
  rm -rf "$tmp"
}

# ───────────────────────── generations ─────────────────────────

cmd_generations() {
  gens() { # préfixe des liens de profil, lien courant
    local prefix="$1" current link n
    current=$(readlink "$2" 2>/dev/null || true)
    for link in "$prefix"-*-link; do
      [ -e "$link" ] || continue
      n=${link##"$prefix"-}
      n=${n%-link}
      printf '%s\t%s\t%s\t%s\n' "$n" "$(stat -c %Y "$link")" \
        "$([ "$(basename "$link")" = "$current" ] && echo 1 || echo 0)" \
        "$(cat "$link/nixos-version" 2>/dev/null || true)"
    done | sort -n | jq -R 'split("\t") | {number: (.[0] | tonumber), time: (.[1] | tonumber),
      current: (.[2] == "1"), version: .[3]}' | jq -s .
  }
  local hm="$HOME/.local/state/nix/profiles/home-manager"
  jq -n --argjson system "$(gens /nix/var/nix/profiles/system /nix/var/nix/profiles/system)" \
    --argjson home "$(gens "$hm" "$hm")" '{system: $system, home: $home}'
}

# ─────────────────────────── weekly ───────────────────────────

# Chercher les mises à jour (routine hebdomadaire, bouton de l'interface) :
# mise à jour du flake dans l'unité de mise à jour (commit de flake.lock,
# sans push), puis préparation en arrière-plan dans tous les cas (Flatpaks),
# qui calcule à la fin ce qui attend d'être installé. Code 0 si flake.lock a
# changé, 3 s'il est inchangé, 1 en cas d'échec.
cmd_check() {
  local before
  if systemctl --user is-active --quiet "$NAME-run.service"; then
    echo "Une mise à jour est en cours : recherche annulée."
    return 1
  fi
  cd "$flake" || {
    notify dialog-warning-symbolic "Mise à jour du système" "Le dossier de configuration n'a pas été trouvé."
    return 1
  }
  before=$(git rev-parse HEAD)
  if [ "$(cfg .routine.flakeUpdate)" != true ]; then
    echo "Mise à jour du flake désactivée dans les réglages : préparation avec le flake.lock actuel."
  elif ! "$NAME" --flake; then
    notify dialog-warning-symbolic "Mise à jour du système" "La mise à jour du flake a échoué."
    return 1
  fi
  mkdir -p "$(dirname "$pending_file")"
  touch "$pending_file"
  systemctl start "$prebuild_unit" || echo "Lancement de la préparation en arrière-plan impossible."
  if [ "$(git rev-parse HEAD)" = "$before" ]; then
    echo "flake.lock inchangé : seulement la préparation des Flatpaks."
    return 3
  fi
}

# Routine hebdomadaire : recherche, puis, si flake.lock a changé,
# notification « Mettre à jour ».
cmd_weekly() { # --manual : lancée depuis l'interface, même si désactivée
  local rc=0 choice
  if [ "${1:-}" != --manual ] && [ "$(cfg .routine.enabled)" != true ]; then
    echo "Routine désactivée dans les réglages."
    exit 0
  fi
  cmd_check || rc=$?
  [ "$rc" -eq 0 ] || exit 0
  [ "$(cfg .routine.notify)" = true ] || exit 0
  # -t 0 : sinon noctalia retire la popup sans signal et le bouton n'existe
  # plus dans l'historique (notify-send attendrait sans fin).
  choice=$(notify software-update-available-symbolic "Mises à jour disponibles" \
    "Préparation en cours en arrière-plan. Sinon, plus tard : @command@" \
    -t 0 -A update="Mettre à jour" -A open="Détails") || true
  case "$choice" in
    update) open_update ;;
    open) systemd-run --user --collect --unit="$NAME-ui-open-$(now)" "$NAME-ui" --show || true ;;
  esac
}

# Applique les réglages de l'interface : horaire de la routine (surcharge
# utilisateur du timer, ou retour à celui de la configuration).
cmd_apply_settings() {
  local cal dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$NAME-weekly.timer.d"
  cal=$(jq -r '.routine.calendar // empty' "$settings_file" 2>/dev/null || true)
  if [ -n "$cal" ]; then
    systemd-analyze calendar "$cal" >/dev/null || die "horaire invalide : $cal"
    mkdir -p "$dir"
    printf '[Timer]\nOnCalendar=\nOnCalendar=%s\n' "$cal" >"$dir/settings.conf"
  else
    rm -f "$dir/settings.conf"
  fi
  systemctl --user daemon-reload
  systemctl --user restart "$NAME-weekly.timer" 2>/dev/null || true
}

# Réglages effectifs de la routine, en JSON (interface).
cmd_settings() {
  local next
  next=$(systemctl --user show "$NAME-weekly.timer" -P NextElapseUSecRealtime 2>/dev/null || true)
  jq -n --argjson r "$(cfg '.routine' | jq -c .)" --arg next "$next" \
    --argjson custom "$([ -r "$settings_file" ] && echo true || echo false)" \
    '$r + {next: $next, custom: $custom}'
}

# Lance la mise à jour depuis un clic : dans l'interface si elle est
# installée, sinon dans un terminal.
open_update() {
  if command -v "$NAME-ui" >/dev/null; then
    "$NAME" --background
    systemd-run --user --collect --unit="$NAME-ui-open-$(now)" "$NAME-ui" --show || true
    return
  fi
  open_terminal "$0" terminal-update
}

# Commande dans un terminal (celui de config.json), dans sa propre unité.
open_terminal() {
  local terminal=()
  mapfile -t terminal < <(jq -r '.terminal[]' "$CONFIG")
  if [ "${#terminal[@]}" -eq 0 ] || ! command -v "${terminal[0]}" >/dev/null; then
    notify dialog-warning-symbolic "Terminal introuvable" "Commande à lancer à la main : $*"
    return 1
  fi
  systemd-run --user --collect --unit="$NAME-terminal-$(now)-$$" \
    "$(command -v "${terminal[0]}")" "${terminal[@]:1}" "$@"
}

# Préparation demandée à la main (interface).
cmd_start_prebuild() {
  mkdir -p "$(dirname "$pending_file")"
  touch "$pending_file"
  systemctl start "$prebuild_unit"
}

# Préparation arrêtée à la main : pas de reprise au prochain démarrage.
cmd_stop_prebuild() {
  rm -f "$pending_file"
  systemctl stop --no-block "$prebuild_unit"
}

# Journal de la préparation en direct, dans un terminal.
cmd_journal() {
  echo "Préparation de la mise à jour (Ctrl+C pour fermer)"
  echo
  journalctl -f -n 40 -o cat -u "$prebuild_unit"
}

# Dans un terminal ouvert par un clic : mise à jour suivie, puis attente.
cmd_terminal_update() {
  "$NAME" || echo "La mise à jour a échoué."
  echo
  read -r -p "Entrée pour fermer. " _ || true
}

cmd_news() {
  if [ ! -e "$news_last" ]; then
    echo "Aucune nouveauté Home Manager depuis la mise en place de cette commande."
    exit 0
  fi
  jq -r '"Nouveautés Home Manager de la mise à jour du \(.date) :\n",
    (.entries[] | "* \(.time[:10])\n\n\(.message)\n")' "$news_last"
}

cmd="${1:-}"
[ $# -eq 0 ] || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  prebuild) cmd_prebuild ;;
  pending) cmd_pending "$@" ;;
  generations) cmd_generations ;;
  weekly) cmd_weekly "$@" ;;
  apply-settings) cmd_apply_settings ;;
  settings) cmd_settings ;;
  check)
    rc=0
    cmd_check || rc=$?
    [ "$rc" -ne 3 ] || rc=0
    exit "$rc"
    ;;
  open-update) open_update ;;
  open-journal) open_terminal "$0" journal ;;
  journal) cmd_journal ;;
  terminal-update) cmd_terminal_update ;;
  news) cmd_news ;;
  boost) cmd_boost ;;
  start-prebuild) cmd_start_prebuild ;;
  stop-prebuild) cmd_stop_prebuild ;;
  *) die "sous-commande inconnue : ${cmd:-(aucune)} (run, prebuild, pending, generations, weekly, news, boost)" ;;
esac
