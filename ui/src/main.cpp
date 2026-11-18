// Interface du centre de mises à jour : icône dans le tray pendant une
// préparation ou une mise à jour (StatusNotifierItem, via QSystemTrayIcon) et fenêtre QML (Qt Quick, style
// KDE : suit kdeglobals). Une seule instance : relancée, elle montre la
// fenêtre de celle qui tourne.
//   --hidden  démarre dans le tray seulement (service de la session)
//   --show    montre la fenêtre (défaut)

#include <QApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSystemTrayIcon>
#include <QTimer>
#include <QFile>
#include <QStandardPaths>
#include <QThread>
#include <QDir>
#include <QFileSystemWatcher>
#include <QPointer>
#include <QUrl>

#include <unistd.h>

#include "backend.h"

// Anneau d'avancement (fraction < 0 : petit arc fixe, inconnue) avec une
// flèche vers le bas ; pastille quand une mise à jour attend.
static QIcon makeIcon(const QColor &accent, bool busy, double fraction, bool badge) {
  const int size = 64;
  QPixmap pix(size, size);
  pix.fill(Qt::transparent);
  QPainter p(&pix);
  p.setRenderHint(QPainter::Antialiasing);
  const QRectF rect(8, 8, size - 16, size - 16);
  QPen pen(QColor(128, 128, 128, busy ? 110 : 200), 7);
  p.setPen(pen);
  p.drawEllipse(rect);
  pen.setColor(accent);
  pen.setWidth(9);
  pen.setCapStyle(Qt::RoundCap);
  p.setPen(pen);
  if (busy) {
    if (fraction < 0)
      p.drawArc(rect, 90 * 16, -40 * 16);
    else if (fraction > 0)
      p.drawArc(rect, 90 * 16, int(-360 * 16 * fraction));
  }
  pen.setWidth(6);
  pen.setColor(busy || badge ? accent : QColor(128, 128, 128, 230));
  p.setPen(pen);
  const int c = size / 2;
  p.drawLine(c, 22, c, 40);
  p.drawLine(c - 7, 33, c, 40);
  p.drawLine(c + 7, 33, c, 40);
  if (badge && !busy) {
    p.setPen(Qt::NoPen);
    p.setBrush(accent);
    p.drawEllipse(QRectF(size - 22, 2, 20, 20));
  }
  p.end();
  return QIcon(pix);
}

int main(int argc, char **argv) {
  QApplication app(argc, argv);
  app.setQuitOnLastWindowClosed(false);
  app.setApplicationName(APP_NAME);
  // Réglages de l'interface (QSettings, ~/.config/<nom>/<nom>.conf).
  app.setOrganizationName(APP_NAME);
  app.setApplicationDisplayName(APP_TITLE);
  // app_id Wayland : règle de fenêtre flottante dans niri.
  app.setDesktopFileName(APP_NAME);
  app.setWindowIcon(QIcon::fromTheme("system-software-update"));

  const QStringList args = app.arguments();
  const bool hidden = args.contains("--hidden");

  // Instance unique. Une autre version déjà lancée (avant une mise à jour)
  // se ferme et laisse la place ; la même version montre sa fenêtre.
  const QString self = QCoreApplication::applicationFilePath();
  const QString socketName = qEnvironmentVariableIsEmpty("UPDATE_CENTER_SOCKET")
                                 ? QString(APP_NAME "-ui-%1").arg(getuid())
                                 : qEnvironmentVariable("UPDATE_CENTER_SOCKET");
  {
    QLocalSocket probe;
    probe.connectToServer(socketName);
    if (probe.waitForConnected(500)) {
      probe.write(("hello " + self + (hidden ? " hidden" : " show") + "\n").toUtf8());
      probe.waitForBytesWritten(500);
      // Pas de réponse : ancienne version sans relève, elle garde la main.
      if (!probe.waitForReadyRead(2000) || !probe.readAll().startsWith("bye")) return 0;
      probe.disconnectFromServer();
      for (int i = 0; i < 50; ++i) {
        QLocalSocket again;
        again.connectToServer(socketName);
        if (!again.waitForConnected(100)) break;
        again.disconnectFromServer();
        QThread::msleep(100);
      }
    }
  }
  QLocalServer::removeServer(socketName);
  QLocalServer server;
  server.listen(socketName);

  if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) QQuickStyle::setStyle("org.kde.desktop");
  QQuickStyle::setFallbackStyle("Fusion");

  Backend backend;
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("backend", &backend);
  // Mode développement (UPDATE_CENTER_QML_DIR=…/ui/qml, cf. ui/dev.sh) : le
  // QML est lu sur le disque et la fenêtre rechargée à chaque modification.
  const QString qmlDir = qEnvironmentVariable("UPDATE_CENTER_QML_DIR");
  if (qmlDir.isEmpty())
    engine.loadFromModule("UpdateCenter", "Main");
  else
    engine.load(QUrl::fromLocalFile(qmlDir + "/Main.qml"));
  if (engine.rootObjects().isEmpty()) return 1;
  QPointer<QQuickWindow> window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());

  auto show = [&window] {
    if (!window) return;
    window->show();
    window->raise();
    window->requestActivate();
  };
  QObject::connect(&server, &QLocalServer::newConnection, [&] {
    QLocalSocket *c = server.nextPendingConnection();
    QObject::connect(c, &QLocalSocket::readyRead, [&, c] {
      const QList<QByteArray> words = c->readAll().trimmed().split(' ');
      if (words.value(0) == "hello" && QString::fromUtf8(words.value(1)) != self) {
        // Nouvelle version : l'état de la fenêtre est déjà dans le fichier
        // de visibilité, on part.
        c->write("bye\n");
        c->flush();
        c->waitForBytesWritten(500);
        app.setProperty("takeover", true);
        QTimer::singleShot(0, &app, [] { QCoreApplication::exit(0); });
        return;
      }
      if (words.value(0) == "show" || words.value(2) == "show") show();
      c->write("same\n");
      c->flush();
      c->deleteLater();
    });
  });

  QSystemTrayIcon tray;
  QMenu menu;
  QAction *status = menu.addAction("");
  status->setEnabled(false);
  menu.addSeparator();
  QObject::connect(menu.addAction(QIcon::fromTheme("window"), "Ouvrir"), &QAction::triggered, show);
  QAction *updateAll = menu.addAction(QIcon::fromTheme("system-software-update"), "Tout mettre à jour");
  QObject::connect(updateAll, &QAction::triggered, [&] {
    backend.startUpdate({});
    show();
  });
  QAction *stopPrebuild = menu.addAction(QIcon::fromTheme("process-stop"), "Arrêter la préparation");
  QObject::connect(stopPrebuild, &QAction::triggered, &backend, &Backend::stopPrebuild);
  menu.addSeparator();
  // exit() et non quit() : quit() demande d'abord la fermeture des fenêtres,
  // que la fenêtre refuse (elle se cache).
  QObject::connect(menu.addAction(QIcon::fromTheme("application-exit"), "Quitter"), &QAction::triggered,
                   &app, [] { QCoreApplication::exit(0); });
  tray.setContextMenu(&menu);
  QObject::connect(&tray, &QSystemTrayIcon::activated, [&](QSystemTrayIcon::ActivationReason r) {
    if (r != QSystemTrayIcon::Trigger) return;
    if (window->isVisible())
      window->hide();
    else
      show();
  });

  auto refreshTray = [&] {
    const bool busy = backend.runActive() || backend.prebuildActive();
    const bool waiting = backend.summary() != "À jour";
    tray.setIcon(makeIcon(app.palette().highlight().color(), busy, backend.progress(), waiting));
    // Mode développement : reconnaître son icône parmi les deux.
    QString tip = (qmlDir.isEmpty() ? QString() : QString(APP_TITLE " (développement)\n")) + backend.summary();
    if (backend.prebuildActive() && !backend.runActive()) {
      const QVariantMap st = backend.prebuild();
      const QVariantMap b = st.value("builds").toMap(), d = st.value("downloads").toMap();
      tip += QString("\nConstructions : %1/%2").arg(b.value("done").toInt()).arg(b.value("expected").toInt());
      tip += QString("\nTéléchargements : %1/%2").arg(d.value("done").toInt()).arg(d.value("expected").toInt());
      const QVariantList building = st.value("building").toList();
      if (!building.isEmpty()) tip += "\nEn cours : " + building.first().toMap().value("name").toString();
      const QString fp = st.value("flatpak").toString();
      if (fp == "running") tip += "\nFlatpak : téléchargement en cours";
      else if (fp == "done") tip += "\nFlatpak : téléchargé";
      if (st.value("boosted").toBool()) tip += "\nÀ pleine vitesse";
    }
    tray.setToolTip(tip);
    status->setText(backend.summary());
    updateAll->setEnabled(!backend.runActive());
    stopPrebuild->setVisible(backend.prebuildActive());
    // Icône seulement pendant que quelque chose tourne (routine,
    // préparation, mise à jour) ou quand une mise à jour préparée attend
    // d'être installée ; sinon la fenêtre s'ouvre depuis le lanceur.
    // Visible tant que la fenêtre est ouverte, pendant une préparation ou
    // une mise à jour, et quand une mise à jour préparée attend.
    tray.setVisible(busy || backend.updateReady() || (window && window->isVisible()));
  };
  QObject::connect(&backend, &Backend::summaryChanged, refreshTray);
  QObject::connect(&backend, &Backend::prebuildChanged, refreshTray);
  QObject::connect(&backend, &Backend::runChanged, refreshTray);
  refreshTray();
  QObject::connect(window.data(), &QWindow::visibleChanged, refreshTray);

  // Fenêtre ouverte ou non, gardée pour la session (XDG_RUNTIME_DIR) : après
  // une mise à jour, la nouvelle version (lancée --hidden par le service)
  // rouvre la fenêtre seulement si elle était ouverte.
  const QString visibleFile = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) +
                              "/" APP_NAME "-ui-visible";
  // Rien n'est écrit pendant la relève : la fenêtre se cache en quittant.
  auto saveVisible = [visibleFile, dev = !qmlDir.isEmpty()](bool visible) {
    if (dev || qApp->property("takeover").toBool()) return;
    QFile f(visibleFile);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) f.write(visible ? "1" : "0");
  };
  bool wasVisible = false;
  {
    QFile f(visibleFile);
    if (f.open(QIODevice::ReadOnly)) wasVisible = f.readAll().trimmed() == "1";
  }
  QObject::connect(window.data(), &QWindow::visibleChanged, saveVisible);
  // « Quitter » : pas de réouverture de la fenêtre au prochain lancement.
  QObject::connect(&app, &QApplication::aboutToQuit, [&] {
    saveVisible(false);
  });
  if (!hidden || wasVisible) show();

  QFileSystemWatcher watcher;
  QTimer reloadTimer;
  if (!qmlDir.isEmpty()) {
    auto title = [&window] {
      if (!window) return;
      window->setTitle(window->title() + " (développement)");
    };
    title();
    auto watchFiles = [&watcher, qmlDir] {
      watcher.addPath(qmlDir);
      for (const QString &f : QDir(qmlDir).entryList({"*.qml"}, QDir::Files))
        watcher.addPath(qmlDir + "/" + f);
    };
    watchFiles();
    reloadTimer.setSingleShot(true);
    reloadTimer.setInterval(250);
    // Nouvelle fenêtre chargée d'abord ; l'ancienne n'est retirée que si le
    // QML se charge (sinon les erreurs s'affichent et elle reste).
    QObject::connect(&reloadTimer, &QTimer::timeout, [&, watchFiles, title] {
      watchFiles();
      const QList<QObject *> old = engine.rootObjects();
      const bool vis = window && window->isVisible();
      const QRect geometry = window ? window->geometry() : QRect();
      engine.clearComponentCache();
      engine.load(QUrl::fromLocalFile(qmlDir + "/Main.qml"));
      if (engine.rootObjects().size() <= old.size()) {
        qWarning("QML en erreur : fenêtre précédente gardée.");
        return;
      }
      for (QObject *o : old) o->deleteLater();
      window = qobject_cast<QQuickWindow *>(engine.rootObjects().last());
      if (!window) return;
      QObject::connect(window.data(), &QWindow::visibleChanged, refreshTray);
      title();
      if (geometry.isValid()) window->setGeometry(geometry);
      if (vis) show();
      qInfo("QML rechargé.");
    });
    QObject::connect(&watcher, &QFileSystemWatcher::fileChanged, &reloadTimer, qOverload<>(&QTimer::start));
    QObject::connect(&watcher, &QFileSystemWatcher::directoryChanged, &reloadTimer, qOverload<>(&QTimer::start));
  }

  // Capture de la fenêtre pour les tests (UPDATE_CENTER_SCREENSHOT=fichier
  // [page], avec QT_QPA_PLATFORM=offscreen), puis sortie.
  const QString shot = qEnvironmentVariable("UPDATE_CENTER_SCREENSHOT");
  if (!shot.isEmpty()) {
    window->setProperty("testTab", qEnvironmentVariableIntValue("UPDATE_CENTER_SCREENSHOT_TAB"));
    QTimer::singleShot(2500, [&window, shot] {
      window->grabWindow().save(shot);
      QCoreApplication::exit(0);
    });
  }
  return app.exec();
}
