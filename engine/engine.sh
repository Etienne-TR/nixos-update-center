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

# « 0 mise à jour », « 1 mise à jour », « 3 mises à jour ».
count() { # nombre, singulier, pluriel
  if [ "$1" -gt 1 ]; then echo "$1 $3"; else echo "$1 $2"; fi
}

# Écrit un fichier JSON d'un coup (lecteurs : jamais de fichier à moitié écrit).
write_json() { # chemin ; JSON sur l'entrée standard
  local tmp="$1.tmp.$$"
  cat >"$tmp" && mv -f "$tmp" "$1"
}

# ───────────────────────────── run ─────────────────────────────

# État de l'exécution, réécrit à chaque changement dans run.json.
run_id="" run_state="" run_step="" run_started=0 run_finished="null" run_log=""
run_progress="null"
# Journal des Flatpaks tant qu'ils tournent en parallèle.
run_flatpak_log=""
part_order=()
declare -A part_label=() part_state=()
notes=()

# Chaque partie a son journal et ses heures : elle forme une action à part
# dans le Journal de l'interface.
declare -A part_log=() part_start=() part_end=()
parts_json() {
  local id
  for id in "${part_order[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "${part_label[$id]}" "${part_state[$id]}" \
      "${part_log[$id]:-}" "${part_start[$id]:-}" "${part_end[$id]:-}"
  done | jq -R 'split("\t") | {id: .[0], label: .[1], state: .[2], log: .[3],
    started: (.[4] | tonumber? // null), finished: (.[5] | tonumber? // null)}' | jq -s .
}

# Une entrée d'historique par partie (« action »), reliées par « group ».
# Notes : celles qui nomment la partie, plus les générales (push…).
write_part_records() {
  local id
  for id in "${part_order[@]}"; do
    jq -c --arg id "$id" --arg group "$run_id" --argjson started "$run_started" --argjson finished "$(now)" '
      (.parts[] | select(.id == $id)) as $p
      | {id: ($group + "-" + $id), group: $group, state: (if $p.state == "running" or $p.state == "pending" then "stopped" else $p.state end),
         started: ($p.started // $started), finished: ($p.finished // $finished), parts: [$p],
         notes: [.notes[] | select(
           if test("^Système") then $id == "system"
           elif test("Home Manager") then $id == "home"
           else true end)],
         log: (if $p.log != "" then $p.log else .log end)}' < <(run_record) >>"$history"
  done
}

notes_json() {
  printf '%s\n' "${notes[@]}" | jq -R . | jq -s 'map(select(length > 0))'
}

run_record() {
  jq -n --arg id "$run_id" --arg state "$run_state" --arg step "$run_step" \
    --argjson started "$run_started" --argjson finished "$run_finished" \
    --argjson parts "$(parts_json)" --argjson notes "$(notes_json)" \
    --arg log "$run_log" --arg flatpakLog "$run_flatpak_log" --argjson progress "$run_progress" --argjson pid "$$" \
    '{id: $id, state: $state, step: $step, started: $started,
      finished: $finished, parts: $parts, notes: $notes, log: $log,
      flatpakLog: $flatpakLog, progress: $progress, pid: $pid}'
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
# flake.lock n'est pas committé ici : il l'est après une application réussie
# (commit_lock), pour que main n'ait que des versions qui ont tourné.
part_flake() {
  nix flake update "${flake_inputs[@]}" || return 1
  if git diff --quiet HEAD -- flake.lock; then
    echo "flake.lock inchangé."
  else
    echo "flake.lock mis à jour (committé après une application réussie)."
  fi
}

# Commit de flake.lock seul (jamais les autres fichiers non committés), avec
# les entrées qui ont changé depuis HEAD dans le message.
commit_lock() {
  git diff --quiet HEAD -- flake.lock && return 0
  local old names
  old=$(mktemp)
  git show HEAD:./flake.lock >"$old" 2>/dev/null || echo '{"nodes":{"root":{"inputs":{}}}}' >"$old"
  names=$(lock_diff_raw "$old" flake.lock | jq -r '[.[].name] | join(", ")')
  rm -f "$old"
  git commit -q -m "chore(flake): mise à jour de ${names:-flake.lock}" -- flake.lock || return 1
  echo "flake.lock committé : ${names:-flake.lock}."
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
# en échec). Sans écrire flake.lock : une entrée ajoutée à flake.nix et pas
# encore verrouillée reste une « nouvelle entrée » à adopter (sinon Nix
# l'ajouterait à flake.lock dès cette évaluation).
differs() { # installable, génération active, fichier où écrire le chemin évalué
  local out err
  err=$(mktemp)
  if ! out=$(nix eval --no-write-lock-file --raw "$1.outPath" 2>"$err"); then
    # Dernière ligne d'erreur de Nix, gardée pour l'interface.
    grep -v '^\s*$' "$err" | tail -n 1 | sed -E 's/^[[:space:]]*(error: )?//' >>"$state/pending-errors.tmp" || true
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

news_count=0
part_home() {
  local old_ids new
  find "$HOME/.config" -name "*.home-manager-backup" -type f -delete 2>/dev/null || true
  find "$HOME" -maxdepth 1 -name "*.home-manager-backup" -type f -delete
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

# Une seule mise à jour Flatpak à la fois (exécution complète, ou
# flatpak-update lancé à côté) : la seconde attend la première.
# Références à mettre à jour (flatpak-update REF…) ; aucune : toutes.
flatpak_refs=() flatpak_commit=""
flatpak_download=""
part_flatpak() {
  (
    flock 7
    # Préparation : télécharger sans installer.
    if [ -n "$flatpak_download" ]; then
      flatpak update --user --no-deploy -y --noninteractive || exit 1
      exit 0
    fi
    # Retour à une version précise (--commit) : une seule référence.
    if [ -n "$flatpak_commit" ]; then
      flatpak update --user -y --noninteractive --commit="$flatpak_commit" "${flatpak_refs[@]}" || exit 1
      exit 0
    fi
    flatpak update --user -y --noninteractive "${flatpak_refs[@]}" || exit 1
    # Sans le bloc « These runtimes … are pinned and won't be removed »
    # répété à chaque fois. pipefail garde l'échec de flatpak.
    flatpak uninstall --user --unused -y --noninteractive 2>&1 |
      awk '/^These runtimes in installation .* are pinned/ { skip = 1; next }
           skip && (/^[[:space:]]/ || /^$/) { next }
           { skip = 0; print }' || exit 1
  ) 7>"$state/flatpak.lock"
}

# Exécution restée « running » alors que son processus n'existe plus (arrêt
# du PC, plantage, kill -9) : notée « interrupted » et ajoutée à
# l'historique, une seule fois. Fin : dernière écriture de son journal.
recover_interrupted() {
  local f pid fin
  for f in "$run_json" "$state/flatpak.json"; do
    [ -s "$f" ] || continue
    [ "$(jq -r '.state // ""' "$f" 2>/dev/null)" = running ] || continue
    pid=$(jq -r '.pid // 0' "$f")
    [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null && continue
    fin=$(stat -c %Y "$(jq -r '.log // ""' "$f")" 2>/dev/null || stat -c %Y "$f")
    jq -c --argjson fin "$fin" '.state = "interrupted" | .finished = $fin | .step = ""
      | .parts |= map(if .state == "running" or .state == "pending" then .state = "interrupted" else . end)' "$f" >"$f.tmp"
    # Une entrée d'historique par partie, comme une exécution terminée.
    jq -c '. as $r | .parts[] as $p
      | {id: ($r.id + "-" + $p.id), group: $r.id, state: $p.state,
         started: ($p.started // $r.started), finished: ($p.finished // $r.finished), parts: [$p],
         notes: $r.notes, log: (if ($p.log // "") != "" then $p.log else $r.log end)}' "$f.tmp" >>"$history"
    mv -f "$f.tmp" "$f"
  done
}

# Mise à jour des Flatpaks seule, à côté d'une exécution Nix (adopter,
# appliquer) : état dans flatpak.json (même forme que run.json), journal à
# part, entrée dans l'historique.
cmd_flatpak_update() { # [--download | --commit C] [REF…] : seulement ces applications (à ce commit)
  recover_interrupted
  [ "$(cfg .flatpak)" = true ] || die "Flatpak désactivé dans la configuration."
  local r
  # Téléchargement seul (préparation), action « flatpak_download ».
  if [ "${1:-}" = --download ]; then
    flatpak_download=1
    shift
  fi
  if [ "${1:-}" = --commit ]; then
    [[ "${2:-}" =~ ^[0-9a-f]{12,64}$ ]] || die "commit invalide : ${2:-}"
    flatpak_commit="$2"
    shift 2
  fi
  for r in "$@"; do
    [[ "$r" =~ ^[A-Za-z0-9._/-]+$ ]] || die "référence Flatpak invalide : $r"
    flatpak_refs+=("$r")
  done
  # Partie : « flatpak » (mise à jour) ou « flatpak_download » (préparation).
  local pn=flatpak
  [ -z "$flatpak_download" ] || pn=flatpak_download
  mkdir -p "$state/runs"
  run_id="$(date +%Y%m%d-%H%M%S)-$pn"
  run_log="$state/runs/$run_id.log"
  run_started=$(now) run_state=running run_step="Mise à jour des Flatpaks"
  [ -z "$flatpak_download" ] || run_step="Téléchargement des Flatpaks"
  part_order=("$pn")
  part_label[$pn]="Flatpak"
  # Une application : son identifiant (app/org.gimp.GIMP/x86_64/stable).
  [ "${#flatpak_refs[@]}" -eq 0 ] || part_label[$pn]="Flatpak ($(printf '%s\n' "${flatpak_refs[@]}" | cut -d/ -f2 | paste -sd, | sed 's/,/, /g'))"
  part_state[$pn]=running
  local out="$state/flatpak.json"
  run_record | write_json "$out"
  trap 'run_state=stopped part_state[$pn]=failed run_finished=$(now); run_record | write_json "$out"; run_record | jq -c . >>"$history"; exit 143' TERM
  if part_flatpak >"$run_log" 2>&1; then
    run_state=success part_state[$pn]=success
  else
    run_state=failed part_state[$pn]=failed
    notify dialog-error-symbolic "Mise à jour des Flatpaks en échec" "Voir le journal : onglet Journal" -t 0
  fi
  run_finished=$(now) run_step=""
  run_record | write_json "$out"
  run_record | jq -c . >>"$history"
  [ "$run_state" = success ]
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
  recover_interrupted
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
  # Garder les 90 derniers journaux (un par partie).
  find "$state/runs" -name '*.log' -printf '%T@ %p\n' | sort -rn | tail -n +91 | cut -d' ' -f2- |
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
  trap 'run_state=stopped run_finished=$(now); write_run; write_part_records; exit 143' TERM

  cd "$flake"
  [ -z "$system$home$flatpak$rollback_system_gen$rollback_home_gen" ] || stop_prebuild

  local failed="" switch_ok="" switch_ko="" id
  # Les Flatpaks ne dépendent pas de Nix : avec d'autres parties, ils sont
  # lancés à part (unité et action à eux, comme « Mettre à jour » de leur
  # carte) et la suite n'attend pas.
  if [ -n "$flatpak" ] && [ "${#part_order[@]}" -gt 1 ]; then
    local o=()
    for id in "${part_order[@]}"; do [ "$id" = flatpak ] || o+=("$id"); done
    part_order=("${o[@]}")
    if systemctl --user is-active --quiet "$NAME-flatpak" ||
      systemd-run --user --collect --quiet --unit="$NAME-flatpak" --setenv=PATH="$PATH" "$0" flatpak-update; then
      echo "Flatpaks : mis à jour à part (action « Mise à jour des Flatpaks »)."
    else
      echo "Lancement des Flatpaks à part impossible : à la suite."
      part_order+=(flatpak)
    fi
    write_run
  fi
  declare -A titles=(
    [flake]="Mise à jour du flake (nix flake update)"
    [system]="Mise à jour du système NixOS"
    [home]="Mise à jour de Home Manager"
    [flatpak]="Mise à jour des Flatpaks"
    [rollback_system]="Retour à une génération système précédente"
    [rollback_home]="Retour à une génération Home Manager précédente"
  )
  # Sorties : fd 5 et 6, celles de l'exécution (journal complet).
  exec 5>&1 6>&2
  local last=""
  for id in "${part_order[@]}"; do
    part_log[$id]="$state/runs/$run_id-$id.log"
    part_start[$id]=$(now)
    last=$id
    # Journal de la partie, en plus du journal complet.
    exec > >(tee -a "${part_log[$id]}" >&5) 2>&1
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
    part_end[$id]=$(now)
    write_run
  done
  # La suite (commit, push, nettoyage) : dans le journal de la dernière
  # partie aussi.
  [ -z "$last" ] || exec > >(tee -a "${part_log[$last]}" >&5) 2>&1

  # flake.lock adopté : committé seulement si tous les switch ont réussi ;
  # un flake.lock qui casse un switch n'est ni committé ni publié.
  local pending push_note=""
  if [ -n "$switch_ok" ] && [ -z "$switch_ko" ] && ! git diff --quiet HEAD -- flake.lock; then
    section "Commit de flake.lock"
    commit_lock || failed=1
  fi
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

  if [ "$news_count" -eq 1 ]; then
    notes+=("1 nouveauté Home Manager : @command@ --news")
  elif [ "$news_count" -gt 1 ]; then
    notes+=("$news_count nouveautés Home Manager : @command@ --news")
  fi
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
  write_part_records

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
  local home rc=0 paths
  home=$(cfg .userHome)
  finish() { # état, chemins construits (JSON)
    jq -n --arg state "$1" --argjson time "$(now)" --argjson paths "${2:-null}" \
      '{state: $state, time: $time, paths: $paths}' | write_json "$prebuild_result"
  }
  trap 'finish stopped; exit 0' TERM

  # Sans NIX_REMOTE=local (celui du service root) : l'utilisateur passe par
  # nix-daemon, sinon « opening lock file …/big-lock: Permission denied ».
  as_user() {
    setpriv --reuid="$user" --regid="$(id -g "$user")" --init-groups -- \
      env -u NIX_REMOTE HOME="$home" XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" "$@"
  }

  # Les Flatpaks sont téléchargés à part (flatpak-download, action à elle).
  cd "$flake"
  echo "Préparation de $host et de Home Manager (construction seule, rien n'est activé)."
  jq -n --argjson t "$(now)" '{phase: "eval", builds: {}, downloads: {}, building: [],
    substituting: [], started: $t, updated: $t}' | write_json "$prebuild_status"
  # Évaluation par l'utilisateur, via nix-daemon : root ne saurait pas
  # récupérer une entrée privée du flake (pas de clé SSH). Les .drv obtenus
  # sont ensuite construits ici, sur le store local, en priorité minimale.
  local drvs sys_drv home_drv
  # Sans écrire flake.lock (voir differs).
  if drvs=$(as_user nix path-info --no-write-lock-file --derivation \
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

# Retour en priorité minimale après « boost ».
cmd_slow() {
  systemctl is-active --quiet "$prebuild_unit" || die "aucune préparation en cours"
  sudo "$root_helper" slow
}

# Pause et reprise de la construction (gel de l'unité, par l'aide root).
cmd_pause_prebuild() { sudo "$root_helper" pause; }
cmd_resume_prebuild() { sudo "$root_helper" resume; }

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
    # Calculée une fois par commit (même en vérification rapide : seulement
    # après une adoption), puis en cache, même vide.
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
      # Échec (réseau, limite de GitHub) : pas de nouvel essai avant 1 h.
      local tried
      tried=$(jq -r --arg k "t:$key" '.[$k] // 0' "$cache" 2>/dev/null || echo 0)
      if ! commits=$(jq -e --arg k "$key" '.[$k]' "$cache" 2>/dev/null) && [ $(($(now) - tried)) -lt 3600 ]; then
        commits=null
      elif [ "$commits" = "" ] || [ "$commits" = null ]; then
        commits=$(curl -fsS --max-time 10 "https://api.github.com/repos/$owner/$repo/compare/$from...$to" 2>/dev/null |
          jq '.ahead_by // null' 2>/dev/null || echo null)
        [ -n "$commits" ] || commits=null
        if [ "$commits" = null ]; then
          jq --arg k "t:$key" --argjson t "$(now)" '.[$k] = $t' "$cache" | write_json "$cache"
        else
          jq --arg k "$key" --argjson c "$commits" '.[$k] = $c' "$cache" | write_json "$cache"
        fi
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

# Mises à jour Flatpak (installation user), en JSON : id, nom, branche,
# version installée et disponible, taille à télécharger, dates des deux
# compilations (secondes).
# Mises à jour Flatpak disponibles, dans flatpaks.json (fichier et verrou à
# part de pending.json : la recherche Flatpak ne dépend pas de Nix et peut
# tourner en même temps qu'une vérification de la config).
cmd_flatpak_pending() {
  mkdir -p "$state"
  exec 9>"$state/flatpaks.lock"
  flock 9
  local list="[]"
  echo "Recherche des mises à jour Flatpak (flatpak remote-ls --updates)…" >&2
  [ "$(cfg .flatpak)" != true ] || list=$(flatpak_updates)
  # Versions proposées : connues avant même leur installation.
  jq '[.[] | select(.commit != "" and .toVersion != "") | {key: .commit[0:12], value: .toVersion}] | from_entries' <<<"$list" |
    flatpak_remember_versions
  echo "  $(count "$(jq length <<<"$list")" "mise à jour disponible" "mises à jour disponibles")" >&2
  jq -n --argjson f "$list" --argjson t "$(now)" '{flatpaks: $f, time: $t}' | write_json "$state/flatpaks.json"
}

# Nom d'une application Flatpak tel que l'affiche le menu d'applications :
# Name (traduit) de la section principale de son raccourci (« Zen Browser »,
# « Tor Browser »). Vide s'il n'y a pas de raccourci (runtime…).
flatpak_desktop_name() {
  local file="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications/$1.desktop"
  [ -f "$file" ] || return 0
  local lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
  lang="${lang%%.*}"
  awk -F= -v full="$lang" -v short="${lang%%_*}" '
    /^\[/ { main = ($0 == "[Desktop Entry]"); next }
    !main { next }
    $1 == "Name[" full "]" && !f { f = substr($0, index($0, "=") + 1) }
    $1 == "Name[" short "]" && !s { s = substr($0, index($0, "=") + 1) }
    $1 == "Name" && !n { n = substr($0, index($0, "=") + 1) }
    END { print (f != "" ? f : s != "" ? s : n) }' "$file"
}

flatpak_updates() {
  local id name dname branch version size origin ref commit installed idate rdate
  # Séparateur non blanc : un champ vide (runtime sans version) ne doit pas
  # décaler les suivants.
  flatpak remote-ls --updates --user --columns=application,name,branch,version,download-size,origin,ref,commit 2>/dev/null |
    tr '\t' '\037' |
    while IFS=$'\037' read -r id name branch version size origin ref commit; do
      [ -n "$ref" ] || continue
      # Nom du raccourci s'il y en a un, sinon celui de Flatpak.
      dname=$(flatpak_desktop_name "$id")
      [ -z "$dname" ] || name=$dname
      installed=$(flatpak info --user "$ref" 2>/dev/null)
      idate=$(sed -nE 's/^ *Date: (.*)$/\1/p' <<<"$installed" | head -n 1)
      rdate=$(flatpak remote-info --user "$origin" "$ref" 2>/dev/null | sed -nE 's/^ *Date: (.*)$/\1/p' | head -n 1)
      jq -n --arg id "$id" --arg name "$name" --arg branch "$branch" --arg to "$version" --arg size "$size" \
        --arg from "$(sed -nE 's/^ *Version: (.*)$/\1/p' <<<"$installed" | head -n 1)" \
        --argjson fromDate "$( [ -n "$idate" ] && date -d "$idate" +%s || echo null)" \
        --argjson toDate "$( [ -n "$rdate" ] && date -d "$rdate" +%s || echo null)" \
        --arg ref "$ref" --arg commit "$commit" \
        '{id: $id, name: $name, branch: $branch, ref: $ref, commit: $commit, fromVersion: $from, toVersion: $to, size: $size,
          fromDate: $fromDate, toDate: $toDate}'
    done | jq -s .
}

# Ce qui attend, en trois tests séparés :
# - config système à appliquer : le système évalué diffère de la génération
#   active (changement de la config ou du flake.lock déjà committé) ;
# - config Home Manager à appliquer : idem pour Home Manager ;
# - nouvelles versions proposées par le flake, et entrées ajoutées à
#   flake.nix pas encore dans flake.lock : nix flake update à blanc
#   (--output-lock-file, flake.lock inchangé).
# Plus le détail : commits et fichiers modifiés depuis la dernière
# application, entrées du flake.lock changées, paquets qui changent (nvd, si
# la préparation a construit), Flatpaks, commits non envoyés.
# Écrit pending.json et l'affiche.
# --quick : seulement git et les fichiers locaux (moins d'une seconde) :
# commits, fichiers modifiés et entrées du flake.lock depuis la dernière
# application ; « à appliquer » déduit de git, sans évaluation. Nouvelles
# versions en ligne et Flatpaks : ceux de la dernière
# vérification complète.
pending_quick=""
cmd_pending() {
  # Ce qui est vérifié : tout (défaut), rien d'autre que git (--quick), ou
  # une seule partie (--only system|home|config|flake|flatpak ; config : les deux premières) ; le reste est
  # repris de la dernière vérification.
  local do_sys=1 do_home=1 do_flake=1 do_flatpak=1 full_nix=""
  # Flatpaks seuls : sans le verrou de pending.json.
  if [ "${1:-}" = --only ] && [ "${2:-}" = flatpak ]; then
    cmd_flatpak_pending
    return
  fi
  case "${1:-}" in
    --quick) pending_quick=1 do_sys="" do_home="" do_flake="" do_flatpak="" ;;
    --only)
      pending_quick=1 do_sys="" do_home="" do_flake="" do_flatpak=""
      case "${2:-}" in
        system) do_sys=1 ;;
        home) do_home=1 ;;
        config) do_sys=1 do_home=1 ;;
        # Tout Nix (config et flake), sans Flatpak : la recherche complète
        # de l'interface lance « nix » et « flatpak » en parallèle.
        nix) do_sys=1 do_home=1 do_flake=1 full_nix=1 ;;
        flake) do_flake=1 ;;
        flatpak) do_flatpak=1 ;;
        *) die "partie inconnue : ${2:-} (system, home, config, nix, flake, flatpak)" ;;
      esac
      ;;
  esac
  local repo rel dir cur tmp prev
  # Une seule vérification à la fois (deux fenêtres, routine…) : la suivante
  # attend la fin de la première.
  mkdir -p "$state"
  exec 8>"$state/pending.lock"
  flock 8
  rm -f "$state/pending-errors.tmp"
  local sys_changed=null home_changed=null upstream="[]" upstream_ok=false upstream_time=0
  local built_sys built_home
  # Vérifiée souvent : rattrape aussi une exécution interrompue.
  recover_interrupted
  local unpushed="[]"
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
  # Config inchangée depuis la vérification précédente : ses évaluations
  # restent valables.
  local same_config=""
  [ "$(jq -r '.head // ""' "$prev")" != "$head" ] || [ "$(jq -r '.dirtyHash // ""' "$prev")" != "$dirty_hash" ] ||
    same_config=1
  local sys_evaluated="" home_evaluated=""
  if [ -n "$do_sys" ]; then
    # Étapes sur stderr : affichées par l'interface (Journal) pendant la
    # recherche.
    echo "Évaluation du système…" >&2
    sys_changed=$(differs "$flake#nixosConfigurations.$host.config.system.build.toplevel" /run/current-system "$tmp/target-sys")
    echo "  système : $([ "$sys_changed" = true ] && echo "à appliquer" || { [ "$sys_changed" = false ] && echo "à jour"; } || echo "évaluation impossible")" >&2
    target_sys=$(cat "$tmp/target-sys" 2>/dev/null || true)
    sys_evaluated=1
  elif [ -n "$same_config" ]; then
    target_sys=$(jq -r '.apply.system.target // ""' "$prev")
    # Génération évaluée connue : la comparer à celle installée maintenant
    # (une application a pu avoir lieu depuis).
    if [ -n "$target_sys" ]; then
      if [ "$(readlink -f /run/current-system)" = "$target_sys" ]; then sys_changed=false; else sys_changed=true; fi
      sys_evaluated=1
    fi
  fi
  if [ -n "$do_home" ]; then
    echo "Évaluation de Home Manager…" >&2
    home_changed=$(differs "$flake#homeConfigurations.$hmconf.activationPackage" \
      "$HOME/.local/state/nix/profiles/home-manager" "$tmp/target-home")
    target_home=$(cat "$tmp/target-home" 2>/dev/null || true)
    echo "  Home Manager : $([ "$home_changed" = true ] && echo "à appliquer" || { [ "$home_changed" = false ] && echo "à jour"; } || echo "évaluation impossible")" >&2
    home_evaluated=1
  elif [ -n "$same_config" ]; then
    target_home=$(jq -r '.apply.home.target // ""' "$prev")
    if [ -n "$target_home" ]; then
      if [ "$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")" = "$target_home" ]; then
        home_changed=false
      else
        home_changed=true
      fi
      home_evaluated=1
    fi
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

  # Parties non évaluées : déduit de git (quelque chose depuis la dernière
  # application ?).
  local fl
  fl=$(jq '(.commits | length) + (.dirty | length)' <<<"$flake_changes")
  [ -n "$sys_evaluated" ] ||
    sys_changed=$(jq --argjson f "$fl" '(.commits | length) + (.dirty | length) + (.inputs | length) + $f > 0' <<<"$sys_changes")
  [ -n "$home_evaluated" ] ||
    home_changed=$(jq --argjson f "$fl" '(.commits | length) + (.dirty | length) + (.inputs | length) + $f > 0' <<<"$home_changes")
  if [ -n "$pending_quick" ]; then
    # Seulement celles que flake.lock n'a pas fait avancer depuis la
    # recherche complète (une entrée mise à jour seule a pu prendre une
    # révision encore plus récente : la prochaine recherche le dira), et
    # les nouvelles entrées toujours absentes de flake.lock.
    upstream=$(jq -c --slurpfile l "$cur" '($l[0]) as $L
      | [.upstream.inputs[]? | select(if .from == null then $L.nodes.root.inputs[.name] == null
          else .from.rev == ($L.nodes[$L.nodes.root.inputs[.name] // ""].locked.rev // "") end)]' \
      "$prev" 2>/dev/null || echo "[]")
    upstream_ok=$(jq -c '.upstream.checked // false' "$prev" 2>/dev/null || echo false)
    upstream_time=$(jq -c '.upstream.time // 0' "$prev" 2>/dev/null || echo 0)
  fi

  # 3 : nouvelles versions proposées par le flake, sans toucher flake.lock.
  [ -z "$do_flake" ] || echo "Recherche des nouvelles versions des entrées du flake (nix flake update à blanc)…" >&2
  if [ -n "$do_flake" ] && (cd "$flake" && nix flake update --output-lock-file "$tmp/new.lock" >/dev/null 2>&1); then
    upstream=$(lock_diff "$cur" "$tmp/new.lock")
    upstream_ok=true upstream_time=$(now)
    echo "  $(count "$(jq length <<<"$upstream")" "nouvelle version en ligne" "nouvelles versions en ligne")" >&2
  fi

  # Flatpaks : aussi toutes les 5 minutes avec la vérification rapide
  # (quelques secondes).
  # En arrière-plan, dans flatpaks.json (voir cmd_flatpak_pending).
  local flatpak_time
  flatpak_time=$(jq '.time // 0' "$state/flatpaks.json" 2>/dev/null || echo 0)
  if [ -n "$pending_quick" ] && [ -z "$do_flatpak" ] && [ $(($(now) - flatpak_time)) -ge 300 ]; then
    do_flatpak=1
  fi
  if [ -n "$do_flatpak" ]; then
    # Sans le verrou de pending.json (fd 8) ni la sortie : la suite n'attend
    # pas la recherche Flatpak.
    (exec 8>&-; cmd_flatpak_pending) >/dev/null 2>&1 &
  fi


  unpushed=$(git -C "$repo" log --format='%h%x09%s' '@{u}..' 2>/dev/null |
    jq -R 'split("\t") | {hash: .[0], subject: .[1]}' | jq -s .)
  # Fichiers non committés du flake (flake.nix et flake.lock compris).
  local uncommitted
  uncommitted=$(git -C "$repo" status --porcelain -- "$dir" 2>/dev/null |
    jq -R -s --arg dir "$dir/" 'split("\n") | map(select(length > 0) | "\(.[0:2]) \(.[3:] | ltrimstr($dir))")')
  # Date de dernière modification de chacun (fichier supprimé : absent).
  local uncommitted_times f
  uncommitted_times=$(jq -r '.[] | .[3:]' <<<"$uncommitted" | while IFS= read -r f; do
    [ -e "$flake/$f" ] && printf '%s\t%s\n' "$f" "$(stat -c %Y "$flake/$f")"
  done | jq -R 'split("\t") | {key: .[0], value: (.[1] | tonumber)}' | jq -s 'from_entries')

  local full_time
  full_time=$(now)
  [ -z "$pending_quick" ] || [ -n "${full_nix:-}" ] || full_time=$(jq '.time // 0' "$prev" 2>/dev/null || echo 0)
  jq -n --argjson time "$full_time" --argjson quickTime "$(now)" \
    --argjson quick "$([ -n "$pending_quick" ] && echo true || echo false)" \
    --argjson sysc "$sys_changed" --argjson homec "$home_changed" \
    --argjson sysch "$sys_changes" --argjson homech "$home_changes" --argjson flakech "$flake_changes" \
    --argjson pkgsys "$pkgs_sys" --argjson pkghome "$pkgs_home" \
    --arg tsys "$target_sys" --arg thome "$target_home" --arg head "$head" --arg dirty "$dirty_hash" \
    --arg sysb "$built_sys" --arg homeb "$built_home" \
    --argjson upstream "$upstream" --argjson uptime "$upstream_time" --argjson upok "$upstream_ok" \
    --argjson unpushed "$unpushed" --argjson uncommitted "$uncommitted" --argjson uncommittedTimes "$uncommitted_times" \
    --argjson errors "$(jq -R . "$state/pending-errors.tmp" 2>/dev/null | jq -s .)" '
    { time: $time, quickTime: $quickTime, quick: $quick, head: $head, dirtyHash: $dirty,
      apply: {
        # built : la préparation a construit exactement la génération de la
        # config actuelle (inconnue sans évaluation de la config).
        system: ({changed: $sysc, built: ($sysb != "" and $sysb == $tsys), target: $tsys, packages: $pkgsys} + $sysch),
        home: ({changed: $homec, built: ($homeb != "" and $homeb == $thome), target: $thome, packages: $pkghome} + $homech),
        flake: ($flakech | {commits, dirty}) },
      upstream: {checked: $upok, inputs: $upstream, time: $uptime},
      unpushed: $unpushed,
      uncommitted: $uncommitted, uncommittedTimes: $uncommittedTimes, errors: $errors }' |
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
    --argjson home "$(gens "$hm" "$hm")" --argjson flatpak "$(flatpak_versions)" \
    '{system: $system, home: $home, flatpak: $flatpak}'
}

# Versions des applications Flatpak installées (installation user), d'après
# le journal de flatpak (commits complets, contrairement à `flatpak
# history`) : chaque déploiement, du plus ancien au plus récent, avec
# « current » pour le commit installé maintenant.
# Numéros de version des Flatpaks, par commit (12 premiers caractères),
# gardés dans flatpak-versions.json : le journal de flatpak ne donne que les
# commits. Complété sans réseau par les applications installées (à chaque
# lecture des versions) et par la recherche de mises à jour (versions
# téléchargées ou proposées). Entrée : objet JSON {commit: version}.
flatpak_remember_versions() {
  local f="$state/flatpak-versions.json" old="{}"
  mkdir -p "$state"
  [ ! -s "$f" ] || old=$(cat "$f")
  jq --argjson old "$old" '$old + .' | write_json "$f"
}

flatpak_versions() {
  [ "$(cfg .flatpak)" = true ] || { echo "[]" && return; }
  # Applications installées : commit actif et nom affiché (celui du menu
  # d'applications, « Zen Browser »).
  local installed ref active name dname dir
  installed=$(flatpak list --user --app --columns=ref,active,name 2>/dev/null |
    while IFS=$'\t' read -r ref active name; do
      dname=$(flatpak_desktop_name "${ref%%/*}")
      # Déploiement actif : son dossier porte le commit complet, sa date
      # celle de l'installation (pour une application sans trace récente
      # dans le journal).
      dir=$(readlink -f "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/app/$ref/active" 2>/dev/null || true)
      jq -n --arg k "app/$ref" --arg a "$active" --arg n "${dname:-$name}" --arg c "${dir##*/}" \
        --argjson t "$( [ -n "$dir" ] && stat -c %Y "$dir" || echo 0)" \
        '{key: $k, value: {active: $a, name: $n, commit: $c, time: $t}}'
    done | jq -s 'from_entries')
  flatpak list --user --app --columns=active,version 2>/dev/null |
    jq -R 'split("\t") | select((.[1] // "") != "") | {key: .[0][0:12], value: .[1]}' | jq -s 'from_entries' |
    flatpak_remember_versions
  local known
  known=$(cat "$state/flatpak-versions.json" 2>/dev/null || echo "{}")
  journalctl -o json --no-pager --since "-90 days" MESSAGE_ID=c7b39b1e006b464599465e105b361485 2>/dev/null |
    jq -c --argjson inst "$installed" --argjson known "$known" '
      select(.INSTALLATION == "user" and (.OPERATION | startswith("deploy")) and (.REF | startswith("app/")))
      | {time: ((.__REALTIME_TIMESTAMP | tonumber) / 1000000 | floor), ref: .REF,
         app: (.REF | split("/")[1]), name: ($inst[.REF].name // ""), commit: .COMMIT, old: (.OLD_COMMIT // ""),
         version: ($known[.COMMIT[0:12]] // ""), operation: .OPERATION, current: (($inst[.REF].active // "") as $a | $a != "" and (.COMMIT | startswith($a)))}' |
    # Applications installées dont la version actuelle n'est plus dans le
    # journal (installées il y a plus de 90 jours) : ajoutées d'après leur
    # déploiement.
    jq -s --argjson inst "$installed" --argjson known "$known" '
      . as $h
      | $h + [$inst | to_entries[] | select(.key as $r | ($h | any(.ref == $r and .current)) | not)
              | {time: .value.time, ref: .key, app: (.key | split("/")[1]), name: .value.name,
                 commit: .value.commit, old: "", version: ($known[.value.active] // ""),
                 operation: "deploy", current: true}]'
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
  before=$(sha256sum flake.lock)
  if [ "$(cfg .routine.flakeUpdate)" != true ]; then
    echo "Mise à jour du flake désactivée dans les réglages : préparation avec le flake.lock actuel."
  elif ! "$NAME" --flake; then
    notify dialog-warning-symbolic "Mise à jour du système" "La mise à jour du flake a échoué."
    return 1
  fi
  mkdir -p "$(dirname "$pending_file")"
  touch "$pending_file"
  systemctl start "$prebuild_unit" || echo "Lancement de la préparation en arrière-plan impossible."
  start_flatpak_download
  if [ "$(sha256sum flake.lock)" = "$before" ]; then
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
  # 3 : flake.lock inchangé, la préparation est lancée quand même ; 1 :
  # échec (déjà notifié).
  [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || exit 0
  # Lancée depuis l'interface : pas de notification, on y est déjà.
  [ "${1:-}" != --manual ] || exit 0
  # Routine : une notification à la fin de chaque préparation, s'il y a
  # quelque chose à installer (Flatpaks téléchargés, constructions Nix).
  notify_flatpak_ready &
  notify_nix_ready &
  wait
}

# Attend la fin d'une unité (« --user » ou système).
wait_unit() { # [--user] unité
  local scope=()
  [ "$1" != --user ] || { scope=(--user) && shift; }
  sleep 5
  while :; do
    case "$(systemctl "${scope[@]}" is-active "$1" 2>/dev/null)" in
      active | activating | reloading | deactivating) sleep 15 ;;
      *) return 0 ;;
    esac
  done
}

# Fin du téléchargement des Flatpaks de la routine : notification s'il y a
# des mises à jour à installer (un échec est déjà notifié).
notify_flatpak_ready() {
  [ "$(cfg .flatpak)" = true ] && [ "$(cfg .routine.flatpak)" = true ] || return 0
  wait_unit --user "$NAME-flatpak"
  [ "$(jq -r '.state // ""' "$state/flatpak.json" 2>/dev/null)" = success ] || return 0
  cmd_flatpak_pending >/dev/null 2>&1 || return 0
  local n choice
  n=$(jq '.flatpaks | length' "$state/flatpaks.json" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] || return 0
  # -t 0 : sinon noctalia retire la popup sans signal et le bouton n'existe
  # plus dans l'historique (notify-send attendrait sans fin).
  choice=$(notify software-update-available-symbolic "Flatpaks prêts à installer" \
    "$(count "$n" "mise à jour téléchargée" "mises à jour téléchargées")." \
    -t 0 -A update="Mettre à jour" -A open="Détails") || true
  case "$choice" in
    update) systemd-run --user --collect --quiet --unit="$NAME-flatpak" --setenv=PATH="$PATH" "$0" flatpak-update || true ;;
    open) systemd-run --user --collect --unit="$NAME-ui-open-$(now)" "$NAME-ui" --show || true ;;
  esac
}

# Fin de la construction Nix de la routine : notification s'il y a une
# nouvelle génération (système ou utilisateur) à activer, ou en cas d'échec.
notify_nix_ready() {
  wait_unit "$prebuild_unit"
  local st n choice body
  st=$(jq -r '.state // ""' "$prebuild_result" 2>/dev/null || true)
  case "$st" in
    success) ;;
    failed)
      notify dialog-error-symbolic "Préparation Nix en échec" "Voir le journal : onglet Journal" -t 0
      return 0
      ;;
    *) return 0 ;;
  esac
  cmd_pending >/dev/null 2>&1 || return 0
  local p="$state/pending.json"
  [ "$(jq '(.system.changed == true) or (.home.changed == true)' "$p" 2>/dev/null)" = true ] || return 0
  n=$(jq '[(.system | select(.changed == true) | .packages // [] | length),
           (.home | select(.changed == true) | .packages // [] | length)] | add // 0' "$p")
  if [ "$n" -gt 0 ]; then
    body="$(count "$n" "paquet" "paquets") à installer."
  else
    body="Nouvelle configuration prête à activer."
  fi
  choice=$(notify software-update-available-symbolic "Mise à jour Nix prête" "$body" \
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
  # Dernier passage daté de maintenant : sinon, avec Persistent, un
  # horaire déjà dépassé depuis le dernier passage lancerait la routine
  # tout de suite au redémarrage du minuteur.
  local stamp="${XDG_DATA_HOME:-$HOME/.local/share}/systemd/timers/stamp-$NAME-weekly.timer"
  [ ! -e "$stamp" ] || touch "$stamp"
  systemctl --user daemon-reload
  systemctl --user restart "$NAME-weekly.timer" 2>/dev/null || true
}

# Réglages effectifs de la routine, en JSON (interface).
cmd_settings() {
  local next
  next=$(systemctl --user show "$NAME-weekly.timer" -P NextElapseUSecRealtime 2>/dev/null || true)
  # Aussi en secondes, pour l'afficher en français dans l'interface.
  local next_time=0
  [ -z "$next" ] || [ "$next" = n/a ] || next_time=$(date -d "$next" +%s 2>/dev/null || echo 0)
  jq -n --argjson r "$(cfg '.routine' | jq -c .)" --arg next "$next" --argjson nextTime "$next_time" \
    --argjson custom "$([ -r "$settings_file" ] && echo true || echo false)" \
    '$r + {next: $next, nextTime: $nextTime, custom: $custom}'
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
# Téléchargement des Flatpaks de la préparation : action à part (unité
# utilisateur, pas besoin de root), lancée avec la construction Nix.
start_flatpak_download() {
  [ "$(cfg .flatpak)" = true ] && [ "$(cfg .routine.flatpak)" = true ] || return 0
  systemctl --user is-active --quiet "$NAME-flatpak" && return 0
  systemd-run --user --collect --quiet --unit="$NAME-flatpak" --setenv=PATH="$PATH" "$0" flatpak-update --download ||
    echo "Lancement du téléchargement des Flatpaks impossible."
}

cmd_start_prebuild() {
  mkdir -p "$(dirname "$pending_file")"
  touch "$pending_file"
  systemctl start "$prebuild_unit"
  start_flatpak_download
}

# Préparation arrêtée à la main : pas de reprise au prochain démarrage.
cmd_stop_prebuild() {
  rm -f "$pending_file"
  # En pause : la dégeler, sinon l'arrêt resterait bloqué.
  [ ! -e "/run/$NAME/paused" ] || sudo "$root_helper" resume >/dev/null || true
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

# Versions d'une application Flatpak encore disponibles sur son dépôt
# (Flathub ne garde qu'un historique court) : commits, en JSON. Une
# requête réseau, lancée à l'ouverture de l'historique de l'application.
cmd_flatpak_history() { # ref (app/…/x86_64/stable)
  local ref="${1:?}" origin
  origin=$(flatpak info --user --show-origin "${ref#app/}" 2>/dev/null) || die "application non installée : $ref"
  flatpak remote-info --user --log "$origin" "$ref" 2>/dev/null |
    sed -nE 's/^ *Commit: ([0-9a-f]+)$/\1/p' | jq -R . | jq -s --arg ref "$ref" '{ref: $ref, commits: .}'
}

cmd="${1:-}"
[ $# -eq 0 ] || shift
case "$cmd" in
  run) cmd_run "$@" ;;
  flatpak-update) cmd_flatpak_update "$@" ;;
  flatpak-history) cmd_flatpak_history "$@" ;;
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
  slow) cmd_slow ;;
  pause-prebuild) cmd_pause_prebuild ;;
  resume-prebuild) cmd_resume_prebuild ;;
  *) die "sous-commande inconnue : ${cmd:-(aucune)} (run, prebuild, pending, generations, weekly, news, boost)" ;;
esac
