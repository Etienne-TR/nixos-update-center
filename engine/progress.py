# Lit sur l'entrée standard le journal de `nix build --log-format
# internal-json -v` et écrit l'avancement dans un fichier JSON (argument),
# lu par l'icône du tray (home-manager/common/update-prebuild-tray.py).
# Écrit aussi dans le journal du service : chaque construction lancée, un
# point toutes les minutes et les erreurs de Nix.
#
# Format de Nix : lignes « @nix {json} ». Activités (start/stop) dont le
# type dit ce qu'elles sont, et résultats (result) rattachés à une activité :
#   activités : 103 copie de chemins (téléchargements), 104 ensemble des
#               constructions, 105 une construction, 108 une substitution ;
#   résultats : 105 avancement [fait, attendu, en cours, en échec] des
#               activités 103 et 104, 106 phase d'une construction.

import json
import os
import re
import sys
import time

ACT_COPY_PATHS, ACT_BUILDS, ACT_BUILD, ACT_SUBSTITUTE = 103, 104, 105, 108
RES_PROGRESS, RES_SET_PHASE = 105, 106

out = sys.argv[1]
ansi = re.compile(r"\x1b\[[0-9;]*m")

acts = {}  # id -> type
progress = {ACT_BUILDS: {}, ACT_COPY_PATHS: {}}  # type -> {id: [4 entiers]}
building = {}  # id -> {"name", "phase"}
substituting = {}  # id -> nom
phase = "eval"
started = time.time()
last_write = 0.0
last_log = time.time()


def name_of(path):
    base = os.path.basename(path)
    if len(base) > 33 and base[32] == "-":
        base = base[33:]
    return base[:-4] if base.endswith(".drv") else base


def totals(kind):
    t = [0, 0, 0, 0]
    for fields in progress[kind].values():
        for i in range(4):
            t[i] += fields[i] if i < len(fields) else 0
    return dict(zip(("done", "expected", "running", "failed"), t))


def state():
    return {
        "phase": phase,
        "builds": totals(ACT_BUILDS),
        "downloads": totals(ACT_COPY_PATHS),
        "building": list(building.values()),
        "substituting": sorted(substituting.values()),
        "started": started,
        "updated": time.time(),
    }


def write(force=False):
    global last_write
    now = time.time()
    if not force and now - last_write < 1:
        return
    last_write = now
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state(), f)
    os.replace(tmp, out)


def log(msg):
    print(msg, flush=True)


def summary():
    b, d = totals(ACT_BUILDS), totals(ACT_COPY_PATHS)
    log(
        f"Constructions {b['done']}/{b['expected']} ({b['failed']} en échec), "
        f"téléchargements {d['done']}/{d['expected']}"
    )


def handle(e):
    global phase
    action = e.get("action")
    if action == "start":
        t = e.get("type")
        acts[e["id"]] = t
        fields = e.get("fields") or []
        if t in (ACT_BUILD, ACT_SUBSTITUTE, ACT_COPY_PATHS, ACT_BUILDS):
            phase = "build"
        if t == ACT_BUILD and fields:
            name = name_of(fields[0])
            building[e["id"]] = {"name": name, "phase": ""}
            log(f"Construction : {name}")
        elif t == ACT_SUBSTITUTE and fields:
            substituting[e["id"]] = name_of(fields[0])
    elif action == "stop":
        acts.pop(e["id"], None)
        building.pop(e["id"], None)
        substituting.pop(e["id"], None)
    elif action == "result":
        t = acts.get(e["id"])
        fields = e.get("fields") or []
        if e.get("type") == RES_PROGRESS and t in progress:
            progress[t][e["id"]] = fields
        elif e.get("type") == RES_SET_PHASE and e["id"] in building and fields:
            building[e["id"]]["phase"] = str(fields[0])
    elif action == "msg" and e.get("level", 9) <= 1:
        log(ansi.sub("", e.get("msg", "")))


write(force=True)
for line in sys.stdin:
    if line.startswith("@nix "):
        try:
            handle(json.loads(line[5:]))
        except (ValueError, KeyError, TypeError):
            pass
    elif line.strip():
        log(ansi.sub("", line.rstrip()))
    write()
    if time.time() - last_log >= 60:
        last_log = time.time()
        summary()

phase = "end"
write(force=True)
summary()
