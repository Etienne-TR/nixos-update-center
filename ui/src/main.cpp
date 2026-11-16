// Interface du centre de mises à jour : icône dans le tray
// (StatusNotifierItem, via QSystemTrayIcon) et fenêtre QML (Qt Quick, style
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
  app.setApplicationDisplayName(APP_TITLE);
  // app_id Wayland : règle de fenêtre flottante dans niri.
  app.setDesktopFileName(APP_NAME);
  app.setWindowIcon(QIcon::fromTheme("system-software-update"));

  const QStringList args = app.arguments();
  const bool hidden = args.contains("--hidden");

  // Instance unique.
  const QString socketName = QString(APP_NAME "-ui-%1").arg(getuid());
  {
    QLocalSocket probe;
    probe.connectToServer(socketName);
    if (probe.waitForConnected(500)) {
      probe.write(hidden ? "noop\n" : "show\n");
      probe.waitForBytesWritten(500);
      return 0;
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
  engine.loadFromModule("UpdateCenter", "Main");
  if (engine.rootObjects().isEmpty()) return 1;
  auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());

  auto show = [window] {
    window->show();
    window->raise();
    window->requestActivate();
  };
  QObject::connect(&server, &QLocalServer::newConnection, [&] {
    QLocalSocket *c = server.nextPendingConnection();
    QObject::connect(c, &QLocalSocket::readyRead, [c, show] {
      if (c->readAll().startsWith("show")) show();
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
  QObject::connect(menu.addAction(QIcon::fromTheme("application-exit"), "Quitter"), &QAction::triggered,
                   &app, &QApplication::quit);
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
    QString tip = backend.summary();
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
  };
  QObject::connect(&backend, &Backend::summaryChanged, refreshTray);
  QObject::connect(&backend, &Backend::prebuildChanged, refreshTray);
  QObject::connect(&backend, &Backend::runChanged, refreshTray);
  refreshTray();
  tray.show();

  if (!hidden) show();

  // Capture de la fenêtre pour les tests (UPDATE_CENTER_SCREENSHOT=fichier
  // [page], avec QT_QPA_PLATFORM=offscreen), puis sortie.
  const QString shot = qEnvironmentVariable("UPDATE_CENTER_SCREENSHOT");
  if (!shot.isEmpty()) {
    window->setProperty("testTab", qEnvironmentVariableIntValue("UPDATE_CENTER_SCREENSHOT_TAB"));
    QTimer::singleShot(2500, [window, shot] {
      window->grabWindow().save(shot);
      QApplication::quit();
    });
  }
  return app.exec();
}
