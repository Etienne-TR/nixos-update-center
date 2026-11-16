// Icône du tray pendant la préparation de la mise à jour en arrière-plan
// (service <name>-prebuild). Lancée par l'unité path du même nom
// quand le fichier d'avancement apparaît, elle se ferme quand il disparaît
// (fin du service) et notifie alors le résultat.
//
// Icône : anneau rempli selon l'avancement de Nix (constructions et
// téléchargements faits / attendus ; le total grossit pendant que Nix
// découvre le travail). Une ligne donne l'état du téléchargement Flatpak.
// Survol : détail. Clic gauche : journal en direct. Clic droit : détail,
// journal, installer maintenant (update), arrêter la préparation.
//
// Qt seul (QtWidgets, sans moc) : QSystemTrayIcon passe par
// StatusNotifierItem, que la barre de Noctalia affiche. En C++ plutôt qu'en
// Python : PyQt6 tirerait QtWebEngine et 2 Go de dépendances.

#include <QApplication>
#include <QDateTime>
#include <QFile>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QProcess>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QTimer>

#include <optional>

static QString env(const char *name, const char *fallback = "") {
  const QString v = qEnvironmentVariable(name);
  return v.isEmpty() ? QString::fromUtf8(fallback) : v;
}

static const QString statusFile = env("PREBUILD_STATUS", "/run/update-prebuild/status.json");
static const QString flatpakFile = env("PREBUILD_FLATPAK", "/run/update-prebuild/flatpak");
static const QString resultFile = env("PREBUILD_RESULT", "/var/lib/update-prebuild/result.json");
static const QString pendingFile = env("PREBUILD_PENDING");
static const QString prebuildUnit = env("PREBUILD_UNIT", "update-prebuild.service");
static const QString engine = env("UPDATE_CENTER_ENGINE");

static std::optional<QJsonObject> readJson(const QString &path) {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return std::nullopt;
  const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
  if (!doc.isObject()) return std::nullopt;
  return doc.object();
}

static void notify(const QString &icon, const QString &title, const QString &body) {
  QProcess::startDetached("notify-send", {"-a", "Mises à jour", "-i", icon, title, body});
}

// Terminal ouvert par le moteur, dans sa propre unité : il survit à la
// fermeture de l'icône (update arrête le service, donc l'icône).
static void engineAction(const QString &action) {
  QProcess::startDetached(engine, {action});
}

// Part du travail faite, ou rien tant que Nix n'a rien annoncé.
static std::optional<double> fraction(const QJsonObject &st) {
  const QJsonObject b = st["builds"].toObject(), d = st["downloads"].toObject();
  const int expected = b["expected"].toInt() + d["expected"].toInt();
  if (expected <= 0) return std::nullopt;
  const int done = b["done"].toInt() + b["failed"].toInt() + d["done"].toInt();
  return qMin(1.0, double(done) / expected);
}

static QIcon makeIcon(std::optional<double> frac) {
  const int size = 64;
  QPixmap pix(size, size);
  pix.fill(Qt::transparent);
  QPainter p(&pix);
  p.setRenderHint(QPainter::Antialiasing);
  const QRectF rect(8, 8, size - 16, size - 16);
  QPen pen(QColor(128, 128, 128, 110), 9);
  p.setPen(pen);
  p.drawEllipse(rect);
  pen.setColor(QColor("#3daee9"));
  pen.setCapStyle(Qt::RoundCap);
  p.setPen(pen);
  if (!frac)
    p.drawArc(rect, 90 * 16, -40 * 16);  // évaluation : petit arc fixe
  else if (*frac > 0)
    p.drawArc(rect, 90 * 16, int(-360 * 16 * *frac));
  // Flèche vers le bas au centre.
  pen.setWidth(6);
  p.setPen(pen);
  const int c = size / 2;
  p.drawLine(c, 22, c, 40);
  p.drawLine(c - 7, 33, c, 40);
  p.drawLine(c + 7, 33, c, 40);
  p.end();
  return QIcon(pix);
}

// État du téléchargement Flatpak : running, done ou failed (vide si absent).
static QString readFlatpakState() {
  QFile f(flatpakFile);
  if (!f.open(QIODevice::ReadOnly)) return QString();
  return QString::fromUtf8(f.readAll()).trimmed();
}

static QStringList describe(const QJsonObject &st) {
  QStringList lines;
  const QString fp = st["flatpak"].toString();
  if (fp == "running") lines << "Flatpak : téléchargement en cours";
  else if (fp == "done") lines << "Flatpak : mises à jour téléchargées";
  else if (fp == "failed") lines << "Flatpak : téléchargement en échec";
  if (st["phase"].toString() == "eval") {
    lines << "Évaluation de la configuration…";
  } else {
    const QJsonObject b = st["builds"].toObject(), d = st["downloads"].toObject();
    if (const auto frac = fraction(st)) lines << QString("Avancement : %1 %").arg(int(*frac * 100));
    QString line = QString("Constructions : %1/%2").arg(b["done"].toInt()).arg(b["expected"].toInt());
    if (b["failed"].toInt() > 0) line += QString(", %1 en échec").arg(b["failed"].toInt());
    lines << line;
    lines << QString("Téléchargements : %1/%2").arg(d["done"].toInt()).arg(d["expected"].toInt());
    const QJsonArray building = st["building"].toArray();
    for (int i = 0; i < building.size() && i < 3; ++i) {
      const QJsonObject item = building[i].toObject();
      const QString phase = item["phase"].toString();
      lines << "En cours : " + item["name"].toString() + (phase.isEmpty() ? "" : " (" + phase + ")");
    }
    if (building.size() > 3) lines << QString("… et %1 autre(s)").arg(building.size() - 3);
    const QJsonArray subst = st["substituting"].toArray();
    if (building.isEmpty() && !subst.isEmpty()) lines << "Téléchargement : " + subst[0].toString();
  }
  if (st.contains("started")) {
    const auto started = QDateTime::fromSecsSinceEpoch(qint64(st["started"].toDouble()));
    lines << "Depuis " + started.toString("HH:mm");
  }
  return lines;
}

int main(int argc, char **argv) {
  QApplication app(argc, argv);
  app.setQuitOnLastWindowClosed(false);
  app.setApplicationName("update-prebuild-tray");
  app.setApplicationDisplayName("Préparation de la mise à jour");
  const qint64 startTime = QDateTime::currentSecsSinceEpoch();

  QSystemTrayIcon tray;
  tray.setIcon(makeIcon(std::nullopt));
  tray.setToolTip("Préparation de la mise à jour");

  QMenu menu;
  QList<QAction *> info;
  for (int i = 0; i < 9; ++i) {
    QAction *a = menu.addAction("");
    a->setEnabled(false);
    a->setVisible(false);
    info << a;
  }
  menu.addSeparator();
  QObject::connect(menu.addAction("Voir le journal en direct"), &QAction::triggered,
                   [] { engineAction("open-journal"); });
  QObject::connect(menu.addAction("Installer maintenant (update)"), &QAction::triggered,
                   [] { engineAction("open-update"); });
  QObject::connect(menu.addAction("Arrêter la préparation"), &QAction::triggered, [] {
    // Arrêt voulu : pas de reprise au prochain démarrage.
    if (!pendingFile.isEmpty()) QFile::remove(pendingFile);
    QProcess::startDetached("systemctl", {"stop", "--no-block", prebuildUnit});
  });
  tray.setContextMenu(&menu);
  QObject::connect(&tray, &QSystemTrayIcon::activated, [](QSystemTrayIcon::ActivationReason r) {
    if (r == QSystemTrayIcon::Trigger) engineAction("open-journal");
  });

  QJsonObject last;
  QTimer timer;
  auto refresh = [&] {
    if (!QFile::exists(statusFile)) {
      // Fin du service : notification du résultat s'il date de cette
      // préparation (rien après un arrêt par update ou par le menu).
      timer.stop();
      const QJsonObject res = readJson(resultFile).value_or(QJsonObject());
      if (res["time"].toDouble() >= startTime - 5) {
        const QString state = res["state"].toString();
        if (state == "success")
          notify("object-select-symbolic", "Mise à jour prête",
                 "Préparée en arrière-plan (Nix construit, Flatpaks téléchargés) : "
                 "update n'a presque plus qu'à l'installer.");
        else if (state == "failed")
          notify("dialog-warning-symbolic", "Préparation incomplète",
                 "Une partie n'a pas pu être construite : update la reprendra "
                 "(journalctl -u " + prebuildUnit + ").");
      }
      tray.hide();
      app.quit();
      return;
    }
    auto st = readJson(statusFile);
    if (!st) return;
    st->insert("flatpak", readFlatpakState());
    if (*st == last) return;
    last = *st;
    const QStringList lines = describe(*st);
    tray.setIcon(makeIcon((*st)["phase"].toString() == "eval" ? std::nullopt : fraction(*st)));
    tray.setToolTip("Préparation de la mise à jour\n" + lines.join("\n"));
    for (int i = 0; i < info.size(); ++i) {
      info[i]->setVisible(i < lines.size());
      if (i < lines.size()) info[i]->setText(lines[i]);
    }
  };
  QObject::connect(&timer, &QTimer::timeout, refresh);
  QTimer::singleShot(0, refresh);
  tray.show();
  timer.start(2000);
  return app.exec();
}
