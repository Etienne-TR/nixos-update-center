#include "backend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include <csignal>

static QString env(const char *name, const QString &fallback) {
  const QString v = qEnvironmentVariable(name);
  return v.isEmpty() ? fallback : v;
}

static QVariantMap readJson(const QString &path) {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return {};
  const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
  return doc.isObject() ? doc.object().toVariantMap() : QVariantMap();
}

static QString readText(const QString &path) {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return {};
  return QString::fromUtf8(f.readAll()).trimmed();
}

static QString stripAnsi(QString s) {
  static const QRegularExpression ansi("\x1b\\[[0-9;?]*[A-Za-z]");
  s.remove(ansi);
  // Retours chariot des barres de progression : garder la dernière version.
  static const QRegularExpression cr("[^\n]*\r(?!\n)");
  s.remove(cr);
  return s;
}

// Part faite d'un avancement de nix build (status.json), -1 si inconnue.
static double nixFraction(const QVariantMap &st) {
  const QVariantMap b = st.value("builds").toMap(), d = st.value("downloads").toMap();
  const int expected = b.value("expected").toInt() + d.value("expected").toInt();
  if (expected <= 0) return -1;
  const int done = b.value("done").toInt() + b.value("failed").toInt() + d.value("done").toInt();
  return qMin(1.0, double(done) / expected);
}

static QString name() { return QStringLiteral(APP_NAME); }

Backend::Backend(QObject *parent) : QObject(parent) {
  const QString stateHome =
      env("XDG_STATE_HOME", QDir::homePath() + "/.local/state");
  m_state = stateHome + "/" + name();
  m_engine = env("UPDATE_CENTER_ENGINE", "/run/current-system/sw/bin/" + name() + "-engine");
  connect(&m_timer, &QTimer::timeout, this, &Backend::poll);
  m_timer.start(1000);
  poll();
  refreshGenerations();
  refreshRoutine();
  refreshPending(true);

  // Config modifiée (flake.nix, flake.lock, commit, git add…) : vérification
  // rapide aussitôt, sans attendre les 5 minutes. Empreinte des dates de
  // modification relue toutes les 3 s.
  const QVariantMap cfg = readJson(env("UPDATE_CENTER_CONFIG", "/etc/" + name() + "/config.json"));
  const QString flake = cfg.value("flake").toString();
  if (!flake.isEmpty()) {
    QString repo = flake;
    while (!repo.isEmpty() && repo != "/" && !QFileInfo::exists(repo + "/.git")) repo = QFileInfo(repo).path();
    // (Pas .git/index : git status, lancé par la vérification, peut le
    // réécrire et la relancerait sans fin.)
    m_watched = {flake + "/flake.nix", flake + "/flake.lock", repo + "/.git/HEAD",
                 repo + "/.git/logs/HEAD"};
    m_configStamp = configStamp();
    connect(&m_configTimer, &QTimer::timeout, this, [this] {
      const QString st = configStamp();
      if (st == m_configStamp) return;
      m_configStamp = st;
      refreshPending(true);
    });
    m_configTimer.start(3000);
  }
}

QString Backend::configStamp() const {
  QString st;
  for (const QString &f : m_watched) st += QString::number(QFileInfo(f).lastModified().toMSecsSinceEpoch()) + ";";
  return st;
}

QString Backend::title() const { return QStringLiteral(APP_TITLE); }

void Backend::engine(const QStringList &args) const { QProcess::startDetached(m_engine, args); }

void Backend::notify(const QString &icon, const QString &title, const QString &body) const {
  QProcess::startDetached("notify-send", {"-a", this->title(), "-i", icon, title, body});
}

void Backend::poll() {
  readRun();
  readFlatpakRun();
  readPrebuild();
  readPending();
  readHistory();
  updateSummary();
}

void Backend::readRun() {
  QVariantMap run = readJson(m_state + "/run.json");
  const qint64 pid = run.value("pid").toLongLong();
  const bool active =
      run.value("state").toString() == "running" && pid > 0 && ::kill(pid_t(pid), 0) == 0;
  run.insert("active", active);
  const QVariantMap build = active ? readJson(m_state + "/build-status.json") : QVariantMap();
  if (run != m_run || build != m_build) {
    const bool wasActive = runActive();
    // Fin d'une exécution, même si elle a été trop courte pour être vue en
    // cours (mise à jour d'une seule entrée du flake) : nouvelle date de fin.
    const bool newlyFinished = !active && !run.value("finished").isNull() &&
                               run.value("finished") != m_run.value("finished") && !m_run.isEmpty();
    m_run = run;
    m_build = build;
    emit runChanged();
    // Fin d'une mise à jour : ce qui attend n'est plus le même.
    if ((wasActive && !active) || newlyFinished) {
      refreshGenerations();
      refreshPending(true);
    }
  }
  readLogTail();
}

void Backend::readFlatpakRun() {
  QVariantMap run = readJson(m_state + "/flatpak.json");
  const qint64 pid = run.value("pid").toLongLong();
  const bool active =
      run.value("state").toString() == "running" && pid > 0 && ::kill(pid_t(pid), 0) == 0;
  run.insert("active", active);
  if (run == m_flatpakRun) return;
  const bool wasActive = m_flatpakRun.value("active").toBool();
  m_flatpakRun = run;
  emit flatpakRunChanged();
  // Fin : nouvelle liste des Flatpaks à mettre à jour.
  if (wasActive && !active) {
    m_flatpakPaused = false;
    refreshPart("flatpak");
  }
}

// Journal de l'exécution, lu au fur et à mesure (derniers 400 Ko).
void Backend::readLogTail() {
  const QString path = m_run.value("log").toString();
  if (path != m_logPath) {
    m_logPath = path;
    m_logPos = 0;
    m_log.clear();
  }
  QFile f(path);
  if (path.isEmpty() || !f.open(QIODevice::ReadOnly)) return;
  if (f.size() < m_logPos) {
    m_logPos = 0;
    m_log.clear();
  }
  if (f.size() == m_logPos) return;
  f.seek(qMax(m_logPos, f.size() - 400 * 1024));
  m_log += stripAnsi(QString::fromUtf8(f.readAll()));
  m_logPos = f.size();
  if (m_log.size() > 400 * 1024) m_log = m_log.right(400 * 1024);
  emit logChanged();
}

void Backend::readPrebuild() {
  const QString dir = "/run/" + name();
  QVariantMap st = readJson(dir + "/status.json");
  if (!st.isEmpty()) {
    st.insert("flatpak", readText(dir + "/flatpak"));
    st.insert("boosted", QFile::exists(dir + "/boosted"));
    st.insert("paused", QFile::exists(dir + "/paused"));
    st.insert("fraction", nixFraction(st));
  }
  const QVariantMap result = readJson("/var/lib/" + name() + "/prebuild.json");
  if (st == m_prebuild && result == m_prebuildResult) return;
  const bool wasActive = prebuildActive();
  if (!wasActive && !st.isEmpty()) m_prebuildSince = QDateTime::currentSecsSinceEpoch();
  m_prebuild = st;
  m_prebuildResult = result;
  emit prebuildChanged();
  // Fin de la préparation : notifiée par la routine (moteur), pas ici.
}

// pending.json, plus flatpaks.json (recherche Flatpak à part) fusionné dedans.
void Backend::readPending() {
  const QString path = m_state + "/pending.json", fpPath = m_state + "/flatpaks.json";
  const QDateTime mtime = QFileInfo(path).lastModified(), fpMtime = QFileInfo(fpPath).lastModified();
  if (mtime == m_pendingMtime && fpMtime == m_flatpaksMtime) return;
  m_pendingMtime = mtime;
  m_flatpaksMtime = fpMtime;
  m_pending = readJson(path);
  const QVariantMap fp = readJson(fpPath);
  m_pending.insert("flatpaks", fp.value("flatpaks").toList());
  m_pending.insert("flatpakTime", fp.value("time"));
  emit pendingChanged();
}

// Éléments en attente : parties dont la config est à appliquer, nouvelles
// versions du flake, Flatpaks.
int Backend::pendingCount() const {
  const QVariantMap apply = m_pending.value("apply").toMap();
  int n = 0;
  const QVariantMap sys = apply.value("system").toMap(), home = apply.value("home").toMap();
  if (sys.value("changed").toBool()) ++n;
  if (home.value("changed").toBool()) ++n;
  // Entrées adoptées sans effet sur l'installation : flake.lock à enregistrer.
  if (n == 0 && (!sys.value("inputs").toList().isEmpty() || !home.value("inputs").toList().isEmpty())) ++n;
  n += m_pending.value("upstream").toMap().value("inputs").toList().size();
  n += m_pending.value("flatpaks").toList().size();
  return n;
}

void Backend::readHistory() {
  const QString path = m_state + "/history.jsonl";
  const QDateTime mtime = QFileInfo(path).lastModified();
  if (mtime == m_historyMtime) return;
  m_historyMtime = mtime;
  QFile f(path);
  QVariantList list;
  if (f.open(QIODevice::ReadOnly)) {
    const QList<QByteArray> lines = f.readAll().split('\n');
    for (auto it = lines.crbegin(); it != lines.crend() && list.size() < 50; ++it) {
      const QJsonDocument doc = QJsonDocument::fromJson(*it);
      if (doc.isObject()) list << doc.object().toVariantMap();
    }
  }
  m_history = list;
  emit historyChanged();
}

// Préparation terminée et quelque chose à installer.
bool Backend::updateReady() const {
  const QVariantMap apply = m_pending.value("apply").toMap();
  return m_prebuildResult.value("state").toString() == "success" &&
         (apply.value("system").toMap().value("changed").toBool() ||
          apply.value("home").toMap().value("changed").toBool() ||
          !m_pending.value("flatpaks").toList().isEmpty());
}

void Backend::updateSummary() {
  QString summary;
  double progress = -1;
  if (runActive()) {
    const QVariantList parts = m_run.value("parts").toList();
    int done = 0;
    for (const QVariant &p : parts) {
      const QString s = p.toMap().value("state").toString();
      if (s == "success" || s == "failed") ++done;
    }
    const QString step = m_run.value("step").toString();
    summary = "Mise à jour en cours" + (step.isEmpty() ? QString() : " : " + step);
    if (!parts.isEmpty()) {
      const double f = nixFraction(m_build);
      progress = (done + (f >= 0 ? f : 0)) / parts.size();
    }
  } else if (prebuildActive()) {
    progress = m_prebuild.value("fraction").toDouble();
    summary = m_prebuild.value("phase").toString() == "eval"
                  ? "Préparation : évaluation de la configuration"
                  : progress >= 0 ? QString("Préparation : %1 %").arg(int(progress * 100))
                                  : "Préparation en cours";
  } else if (updateReady()) {
    summary = "Mise à jour prête à installer";
  } else if (pendingCount() > 0) {
    summary = QString(pendingCount() > 1 ? "%1 éléments en attente" : "%1 élément en attente").arg(pendingCount());
  } else {
    summary = "À jour";
  }
  if (summary != m_summary || !qFuzzyCompare(progress + 2, m_progress + 2)) {
    m_summary = summary;
    m_progress = progress;
    emit summaryChanged();
  }
}

void Backend::startUpdate(const QStringList &parts) {
  QProcess::startDetached(QStringLiteral(APP_NAME), QStringList{"--background"} + parts);
  emit runStarted();
}

// La routine elle-même (même notification), dans sa propre unité : elle
// survit à un redémarrage de l'interface (switch Home Manager).
void Backend::checkUpdates() {
  QProcess::startDetached("systemd-run", {"--user", "--collect", "--quiet",
                                          QStringLiteral("--unit=" APP_NAME "-weekly-now"),
                                          "--setenv=PATH=" + qEnvironmentVariable("PATH"), m_engine,
                                          "weekly", "--manual"});
  emit runStarted();
}

void Backend::startFlatpakUpdate(const QStringList &refs) {
  QProcess::startDetached("systemd-run", QStringList{"--user", "--collect", "--quiet",
                                                     QStringLiteral("--unit=" APP_NAME "-flatpak"),
                                                     "--setenv=PATH=" + qEnvironmentVariable("PATH"),
                                                     m_engine, "flatpak-update"} + refs);
}

void Backend::stopFlatpak() {
  QProcess::startDetached("systemctl", {"--user", "thaw", QStringLiteral(APP_NAME "-flatpak")});
  QProcess::startDetached("systemctl", {"--user", "stop", "--no-block", QStringLiteral(APP_NAME "-flatpak")});
  m_flatpakPaused = false;
  emit flatpakRunChanged();
}

// Gel de l'unité (cgroup) : flatpak s'arrête net et reprend où il en était.
void Backend::pauseFlatpak(bool paused) {
  QProcess::startDetached("systemctl", {"--user", paused ? "freeze" : "thaw", QStringLiteral(APP_NAME "-flatpak")});
  m_flatpakPaused = paused;
  emit flatpakRunChanged();
}

void Backend::stopCheck(const QString &part) {
  if (QProcess *p = m_checkProcs.value(part)) p->terminate();
}

void Backend::runEngine(const QStringList &args, std::function<void(int, const QByteArray &)> done) {
  auto *p = new QProcess(this);
  connect(p, &QProcess::finished, this, [p, done](int code) {
    p->deleteLater();
    done(code, p->readAllStandardOutput() + p->readAllStandardError());
  });
  p->start(m_engine, args);
}

// Interroge le dépôt (Flathub) sur les versions encore disponibles d'une
// application. Le résultat précédent reste affiché pendant la requête
// (sinon la sélection clignote) ; il est remplacé à la réponse.
void Backend::checkFlatpakHistory(const QString &ref) {
  runEngine({"flatpak-history", ref}, [this, ref](int code, const QByteArray &out) {
    QVariantMap r;
    if (code == 0)
      r.insert("commits", QJsonDocument::fromJson(out).object().value("commits").toArray().toVariantList());
    else
      r.insert("error", true);
    m_flatpakAvailable.insert(ref, r);
    emit flatpakAvailableChanged();
  });
}

void Backend::refreshRoutine() {
  runEngine({"settings"}, [this](int, const QByteArray &out) {
    m_routine = QJsonDocument::fromJson(out).object().toVariantMap();
    emit routineChanged();
  });
}

static QString settingsPath() {
  return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/" APP_NAME
                                                                                  "/settings.json";
}

// Écrit ~/.config/<name>/settings.json puis l'applique (horaire du timer).
void Backend::saveRoutine(const QVariantMap &routine) {
  QDir().mkpath(QFileInfo(settingsPath()).absolutePath());
  QFile f(settingsPath());
  if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
    emit error("Impossible d'écrire " + settingsPath());
    return;
  }
  QJsonObject root;
  root.insert("routine", QJsonObject::fromVariantMap(routine));
  f.write(QJsonDocument(root).toJson());
  f.close();
  runEngine({"apply-settings"}, [this](int code, const QByteArray &out) {
    if (code != 0) emit error(QString::fromUtf8(out).trimmed());
    refreshRoutine();
  });
}

void Backend::resetRoutine() {
  QFile::remove(settingsPath());
  runEngine({"apply-settings"}, [this](int, const QByteArray &) { refreshRoutine(); });
}

void Backend::updateInput(const QString &name) { startUpdate({"--flake-input", name}); }

void Backend::stopRun() { QProcess::startDetached(QStringLiteral(APP_NAME), {"--stop"}); }
void Backend::startPrebuild() { engine({"start-prebuild"}); }
void Backend::stopPrebuild() { engine({"stop-prebuild"}); }
void Backend::boostPrebuild(bool boost) { engine({boost ? "boost" : "slow"}); }
void Backend::pausePrebuild(bool paused) { engine({paused ? "pause-prebuild" : "resume-prebuild"}); }
// 400 dernières lignes du journal du service de préparation.
void Backend::refreshPrebuildLog() {
  if (m_prebuildLogBusy) return;
  m_prebuildLogBusy = true;
  auto *p = new QProcess(this);
  connect(p, &QProcess::finished, this, [this, p] {
    p->deleteLater();
    m_prebuildLogBusy = false;
    const QString text = QString::fromUtf8(p->readAllStandardOutput());
    if (text != m_prebuildLog) {
      m_prebuildLog = text;
      emit prebuildLogChanged();
    }
  });
  p->start("journalctl", {"-u", QStringLiteral(APP_NAME "-prebuild.service"), "-o", "cat", "-n", "400",
                          "--no-pager"});
}

void Backend::openPrebuildJournal() { engine({"open-journal"}); }

void Backend::rollbackSystem(int generation) {
  startUpdate({"--rollback-system", QString::number(generation)});
}

void Backend::rollbackHome(int generation) {
  startUpdate({"--rollback-home", QString::number(generation)});
}

// Plusieurs vérifications peuvent tourner en même temps (Flatpak à côté de
// la config) ; la même deux fois, ou n'importe laquelle pendant une
// complète, est ignorée.
void Backend::runPending(const QStringList &args) {
  const QString key = args.contains("--quick") ? QStringLiteral("quick")
                      : args.indexOf("--only") >= 0 ? args.value(args.indexOf("--only") + 1)
                                                     : QStringLiteral("all");
  if (m_pendingParts.contains(key) || m_pendingParts.contains("all")) return;
  m_pendingParts.append(key);
  emit pendingChanged();
  auto *p = new QProcess(this);
  // Recherche visible (pas la rapide) : ses étapes pour le Journal.
  if (key != "quick") {
    m_checkLog = QString("$ nixos-update-center-engine pending %1\n").arg(args.join(' '));
    emit checkLogChanged();
    connect(p, &QProcess::readyReadStandardError, this, [this, p] {
      m_checkLog += QString::fromUtf8(p->readAllStandardError());
      emit checkLogChanged();
    });
  }
  m_checkProcs.insert(key, p);
  connect(p, &QProcess::finished, this, [this, p, key] {
    p->deleteLater();
    m_checkProcs.remove(key);
    m_pendingParts.removeOne(key);
    m_pendingMtime = QDateTime();
    readPending();
    emit pendingChanged();
  });
  p->start(m_engine, QStringList{"pending"} + args);
}

// Recherche complète : deux actions indépendantes, Nix et Flatpak, en
// parallèle.
void Backend::refreshPending(bool quick) {
  if (quick) return runPending({"--quick"});
  runPending({"--only", "nix"});
  runPending({"--only", "flatpak"});
}

void Backend::refreshPart(const QString &part) { runPending({"--only", part}); }

void Backend::refreshGenerations() {
  auto *p = new QProcess(this);
  connect(p, &QProcess::finished, this, [this, p] {
    p->deleteLater();
    const QJsonDocument doc = QJsonDocument::fromJson(p->readAllStandardOutput());
    m_generations = doc.object().toVariantMap();
    auto *n = new QProcess(this);
    connect(n, &QProcess::finished, this, [this, n] {
      n->deleteLater();
      m_news = QString::fromUtf8(n->readAllStandardOutput()).trimmed();
      emit generationsChanged();
    });
    n->start(m_engine, {"news"});
  });
  p->start(m_engine, {"generations"});
}

QString Backend::readLog(const QString &path) const {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return "Journal introuvable (seuls les 30 derniers sont gardés).";
  return stripAnsi(QString::fromUtf8(f.readAll()));
}

QString Backend::formatTime(double secs) const {
  if (secs <= 0) return {};
  const QDateTime t = QDateTime::fromSecsSinceEpoch(qint64(secs));
  const QDate today = QDate::currentDate();
  QLocale fr(QLocale::French);
  if (t.date() == today) return "aujourd'hui à " + t.toString("HH:mm");
  if (t.date() == today.addDays(-1)) return "hier à " + t.toString("HH:mm");
  // Cette semaine : le jour seul (« lundi à 12:05 ») ; sinon la date, sans
  // l'année si c'est la même (« le 20 novembre à 12:05 »).
  if (t.date() == today.addDays(1)) return "demain à " + t.toString("HH:mm");
  // À venir dans la semaine (routine) : le jour seul aussi.
  if (t.date() > today && t.date() < today.addDays(7)) return fr.toString(t, "dddd 'à' HH:mm");
  if (t.date() < today && t.date() > today.addDays(-7)) return fr.toString(t, "dddd 'à' HH:mm");
  if (t.date().year() == today.year()) return "le " + fr.toString(t, "d MMMM 'à' HH:mm");
  return "le " + fr.toString(t, "d MMMM yyyy 'à' HH:mm");
}

QString Backend::formatBytes(double bytes) const {
  return QLocale(QLocale::French).formattedDataSize(qint64(bytes));
}
