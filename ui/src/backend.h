// Lit les états JSON du moteur et lance ses commandes, pour l'interface QML
// et l'icône du tray.
#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

class Backend : public QObject {
  Q_OBJECT
  // Exécution en cours ou dernière (run.json), avec « active ».
  Q_PROPERTY(QVariantMap run READ run NOTIFY runChanged)
  // Avancement de la construction en cours pendant une exécution.
  Q_PROPERTY(QVariantMap build READ build NOTIFY runChanged)
  // Mise à jour des Flatpaks lancée seule (flatpak.json), avec « active ».
  Q_PROPERTY(QVariantMap flatpakRun READ flatpakRun NOTIFY flatpakRunChanged)
  Q_PROPERTY(QString log READ log NOTIFY logChanged)
  // Journal du service de préparation (journalctl), lu à la demande.
  Q_PROPERTY(QString prebuildLog READ prebuildLog NOTIFY prebuildLogChanged)
  // Préparation en arrière-plan : avancement (vide si elle ne tourne pas),
  // résultat de la dernière.
  Q_PROPERTY(bool prebuildActive READ prebuildActive NOTIFY prebuildChanged)
  Q_PROPERTY(QVariantMap prebuild READ prebuild NOTIFY prebuildChanged)
  Q_PROPERTY(QVariantMap prebuildResult READ prebuildResult NOTIFY prebuildChanged)
  Q_PROPERTY(QVariantMap pending READ pending NOTIFY pendingChanged)
  Q_PROPERTY(bool pendingBusy READ pendingBusy NOTIFY pendingChanged)
  // Vérification en cours de type rapide (git seulement, moins d'une seconde).
  Q_PROPERTY(bool pendingQuick READ pendingQuick NOTIFY pendingChanged)
  // Partie vérifiée en ce moment : all, system, home, flake, flatpak.
  Q_PROPERTY(QString pendingPart READ pendingPart NOTIFY pendingChanged)
  // Vérifications en cours, en même temps : quick, all, system, home,
  // config, flake, flatpak.
  Q_PROPERTY(QStringList pendingParts READ pendingParts NOTIFY pendingChanged)
  Q_PROPERTY(int pendingCount READ pendingCount NOTIFY pendingChanged)
  Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
  Q_PROPERTY(QVariantMap generations READ generations NOTIFY generationsChanged)
  Q_PROPERTY(QString news READ news NOTIFY generationsChanged)
  // Résumé d'une ligne et part du travail faite (-1 : inconnue), communs
  // à la fenêtre et au tray.
  Q_PROPERTY(QString summary READ summary NOTIFY summaryChanged)
  Q_PROPERTY(double progress READ progress NOTIFY summaryChanged)
  Q_PROPERTY(QString title READ title CONSTANT)
  // Réglages effectifs de la routine (config.json, puis settings.json).
  Q_PROPERTY(QVariantMap routine READ routine NOTIFY routineChanged)

 public:
  explicit Backend(QObject *parent = nullptr);

  QVariantMap run() const { return m_run; }
  QVariantMap build() const { return m_build; }
  QVariantMap flatpakRun() const { return m_flatpakRun; }
  QString log() const { return m_log; }
  QString prebuildLog() const { return m_prebuildLog; }
  bool prebuildActive() const { return !m_prebuild.isEmpty(); }
  QVariantMap prebuild() const { return m_prebuild; }
  QVariantMap prebuildResult() const { return m_prebuildResult; }
  QVariantMap pending() const { return m_pending; }
  bool pendingBusy() const { return !m_pendingParts.isEmpty(); }
  // Seulement des vérifications rapides en cours.
  bool pendingQuick() const { return m_pendingParts == QStringList{"quick"}; }
  // Première vérification en cours autre que la rapide.
  QString pendingPart() const {
    for (const QString &p : m_pendingParts)
      if (p != "quick") return p;
    return {};
  }
  QStringList pendingParts() const { return m_pendingParts; }
  // Cette partie (system, home, config, flake, flatpak) est-elle en cours
  // de vérification (seule ou dans une complète) ?
  Q_INVOKABLE bool checking(const QString &part) const {
    return m_pendingParts.contains(part) || m_pendingParts.contains("all") ||
           (part == "config" && (m_pendingParts.contains("system") || m_pendingParts.contains("home")));
  }
  int pendingCount() const;
  QVariantList history() const { return m_history; }
  QVariantMap generations() const { return m_generations; }
  QString news() const { return m_news; }
  QString summary() const { return m_summary; }
  double progress() const { return m_progress; }
  QString title() const;
  bool runActive() const { return m_run.value("active").toBool(); }
  bool updateReady() const;
  QVariantMap routine() const { return m_routine; }

  Q_INVOKABLE void startUpdate(const QStringList &parts);
  Q_INVOKABLE void checkUpdates();
  // Flatpaks seuls, dans leur propre unité : possible pendant une exécution.
  Q_INVOKABLE void startFlatpakUpdate();
  // nix flake update <entrée> (commit de flake.lock), dans l'unité de mise à jour.
  Q_INVOKABLE void updateInput(const QString &name);
  Q_INVOKABLE void refreshRoutine();
  Q_INVOKABLE void saveRoutine(const QVariantMap &routine);
  Q_INVOKABLE void resetRoutine();
  Q_INVOKABLE void stopRun();
  Q_INVOKABLE void startPrebuild();
  Q_INVOKABLE void stopPrebuild();
  Q_INVOKABLE void boostPrebuild();
  Q_INVOKABLE void openPrebuildJournal();
  Q_INVOKABLE void refreshPrebuildLog();
  // quick : git seulement (démarrage, ouverture, toutes les 5 minutes).
  Q_INVOKABLE void refreshPending(bool quick = false);
  // Une seule partie : system, home, flake ou flatpak.
  Q_INVOKABLE void refreshPart(const QString &part);
  Q_INVOKABLE void refreshGenerations();
  Q_INVOKABLE void rollbackSystem(int generation);
  Q_INVOKABLE void rollbackHome(int generation);
  Q_INVOKABLE QString readLog(const QString &path) const;
  Q_INVOKABLE QString formatTime(double secs) const;
  Q_INVOKABLE QString formatBytes(double bytes) const;

 signals:
  void runChanged();
  void flatpakRunChanged();
  void logChanged();
  void prebuildLogChanged();
  void prebuildChanged();
  void pendingChanged();
  void historyChanged();
  void generationsChanged();
  void summaryChanged();
  void routineChanged();
  // Erreur à montrer (réglages refusés…).
  void error(const QString &message);
  // Une exécution vient d'être lancée depuis l'interface.
  void runStarted();

 private:
  void poll();
  void readRun();
  void readFlatpakRun();
  void readLogTail();
  void readPrebuild();
  void readPending();
  void readHistory();
  void updateSummary();
  void engine(const QStringList &args) const;
  void notify(const QString &icon, const QString &title, const QString &body) const;

  QString m_state, m_engine;
  QTimer m_timer;
  QVariantMap m_routine;
  QStringList m_watched;
  QString m_configStamp;
  QTimer m_configTimer;
  QString configStamp() const;
  void runPending(const QStringList &args);
  void runEngine(const QStringList &args, std::function<void(int, const QByteArray &)> done);
  QVariantMap m_flatpakRun;
  QVariantMap m_run, m_build, m_prebuild, m_prebuildResult, m_pending, m_generations;
  QVariantList m_history;
  QString m_prebuildLog;
  bool m_prebuildLogBusy = false;
  QString m_log, m_logPath, m_news, m_summary;
  qint64 m_logPos = 0;
  double m_progress = -1;
  QStringList m_pendingParts;
  QDateTime m_pendingMtime, m_flatpaksMtime, m_historyMtime;
  qint64 m_prebuildSince = 0;
};
