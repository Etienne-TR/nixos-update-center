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
}

QString Backend::title() const { return QStringLiteral(APP_TITLE); }

void Backend::engine(const QStringList &args) const { QProcess::startDetached(m_engine, args); }

void Backend::notify(const QString &icon, const QString &title, const QString &body) const {
  QProcess::startDetached("notify-send", {"-a", this->title(), "-i", icon, title, body});
}

void Backend::poll() {
  readRun();
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
    m_run = run;
    m_build = build;
    emit runChanged();
    // Fin d'une mise à jour : ce qui attend n'est plus le même.
    if (wasActive && !active) {
      refreshGenerations();
      refreshPending(true);
    }
  }
  readLogTail();
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
    st.insert("fraction", nixFraction(st));
  }
  const QVariantMap result = readJson("/var/lib/" + name() + "/prebuild.json");
  if (st == m_prebuild && result == m_prebuildResult) return;
  const bool wasActive = prebuildActive();
  if (!wasActive && !st.isEmpty()) m_prebuildSince = QDateTime::currentSecsSinceEpoch();
  m_prebuild = st;
  m_prebuildResult = result;
  emit prebuildChanged();
  // Fin de la préparation : résultat notifié s'il date d'elle (rien après
  // un arrêt).
  if (wasActive && st.isEmpty() && result.value("time").toDouble() >= m_prebuildSince - 5) {
    const QString state = result.value("state").toString();
    if (state == "success")
      notify("object-select-symbolic", "Mise à jour prête",
             "Préparée en arrière-plan : il ne reste presque plus qu'à l'installer.");
    else if (state == "failed")
      notify("dialog-warning-symbolic", "Préparation incomplète",
             "Une partie n'a pas pu être préparée : la mise à jour la reprendra.");
  }
}

void Backend::readPending() {
  const QString path = m_state + "/pending.json";
  const QDateTime mtime = QFileInfo(path).lastModified();
  if (mtime == m_pendingMtime) return;
  m_pendingMtime = mtime;
  m_pending = readJson(path);
  emit pendingChanged();
}

// Éléments en attente : parties dont la config est à appliquer, nouvelles
// versions du flake, Flatpaks, Claude Desktop.
int Backend::pendingCount() const {
  const QVariantMap apply = m_pending.value("apply").toMap();
  int n = 0;
  if (apply.value("system").toMap().value("changed").toBool()) ++n;
  if (apply.value("home").toMap().value("changed").toBool()) ++n;
  n += m_pending.value("upstream").toMap().value("inputs").toList().size();
  n += m_pending.value("flatpaks").toList().size();
  if (m_pending.value("claudeDesktop").toMap().value("available").toBool()) ++n;
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
    summary = QString("%1 élément(s) en attente").arg(pendingCount());
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

void Backend::runEngine(const QStringList &args, std::function<void(int, const QByteArray &)> done) {
  auto *p = new QProcess(this);
  connect(p, &QProcess::finished, this, [p, done](int code) {
    p->deleteLater();
    done(code, p->readAllStandardOutput() + p->readAllStandardError());
  });
  p->start(m_engine, args);
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
void Backend::boostPrebuild() { engine({"boost"}); }
void Backend::openPrebuildJournal() { engine({"open-journal"}); }

void Backend::rollbackSystem(int generation) {
  startUpdate({"--rollback-system", QString::number(generation)});
}

void Backend::rollbackHome(int generation) {
  startUpdate({"--rollback-home", QString::number(generation)});
}

void Backend::refreshPending(bool quick) {
  if (m_pendingBusy) return;
  m_pendingBusy = true;
  emit pendingChanged();
  auto *p = new QProcess(this);
  connect(p, &QProcess::finished, this, [this, p] {
    p->deleteLater();
    m_pendingBusy = false;
    m_pendingMtime = QDateTime();
    readPending();
    emit pendingChanged();
  });
  p->start(m_engine, quick ? QStringList{"pending", "--quick"} : QStringList{"pending"});
}

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
  return fr.toString(t, "d MMMM yyyy 'à' HH:mm");
}

QString Backend::formatBytes(double bytes) const {
  return QLocale(QLocale::French).formattedDataSize(qint64(bytes));
}
