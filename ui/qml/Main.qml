import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ApplicationWindow {
    id: window
    title: backend.title
    width: 820
    height: 680
    minimumWidth: 520
    minimumHeight: 420
    visible: false

    // Vérification rapide (git seulement) à l'ouverture de la fenêtre et
    // toutes les 5 minutes tant qu'elle est ouverte ; la complète se lance
    // par le bouton « Rechercher ».
    onVisibleChanged: if (visible && !backend.pendingBusy) backend.refreshPending(true)
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: window.visible
        onTriggered: if (!backend.pendingBusy) backend.refreshPending(true)
    }

    // Fermer la fenêtre la cache : l'icône reste dans le tray.
    onClosing: (close) => { close.accepted = false; window.hide(); }

    readonly property bool running: backend.run.active === true

    // Date relative (« aujourd'hui à… », « hier à… ») : recalculée chaque
    // minute, pour que « aujourd'hui » suive le jour de l'affichage.
    property real now: Date.now()
    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: window.now = Date.now()
    }
    function when(secs) { return window.now, backend.formatTime(secs); }
    // Onglet imposé pour les captures de test.
    property int testTab: -1
    onTestTabChanged: if (testTab >= 0) tabs.currentIndex = testTab

    // Couleurs d'état, communes aux pages.
    function stateColor(state) {
        switch (state) {
        case "success": return Kirigami.Theme.positiveTextColor;
        case "failed": return Kirigami.Theme.negativeTextColor;
        case "partial": case "stopped": return Kirigami.Theme.neutralTextColor;
        case "running": return Kirigami.Theme.highlightColor;
        default: return Kirigami.Theme.disabledTextColor;
        }
    }
    function stateGlyph(state) {
        switch (state) {
        case "success": return "✓";
        case "failed": return "✗";
        case "running": return "●";
        default: return "○";
        }
    }
    function runTitle(state) {
        switch (state) {
        case "running": return "Mise à jour en cours";
        case "success": return "Mise à jour terminée";
        case "partial": return "Mise à jour incomplète";
        case "failed": return "Mise à jour en échec";
        case "stopped": return "Mise à jour arrêtée";
        default: return "Aucune mise à jour lancée";
        }
    }

    function showRunTab() { tabs.currentIndex = 1; }


    // Confirmation avant une action lourde (arrêt, retour arrière).
    Dialog {
        id: confirm
        property var action
        property alias message: confirmText.text
        anchors.centerIn: parent
        modal: true
        width: Math.min(window.width - 40, 460)
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            id: confirmText
            width: parent.width
            wrapMode: Text.WordWrap
        }
        onAccepted: action()
    }
    function ask(title, message, action) {
        confirm.title = title;
        confirm.message = message;
        confirm.action = action;
        confirm.open();
    }

    // Journal d'une exécution passée.
    Dialog {
        id: logViewer
        property alias text: logText.text
        anchors.centerIn: parent
        modal: true
        width: window.width - 40
        height: window.height - 40
        standardButtons: Dialog.Close
        MonoText {
            id: logText
            anchors.fill: parent
        }
    }
    function showLog(title, path) {
        logViewer.title = title;
        logViewer.text = backend.readLog(path);
        logViewer.open();
    }

    header: ToolBar {
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            TabBar {
                id: tabs
                Layout.fillWidth: true
                TabButton {
                    text: backend.pendingCount > 0 ? "En attente (" + backend.pendingCount + ")" : "En attente"
                }
                TabButton { text: window.running ? "En cours ●" : "En cours" }
                TabButton { text: "Historique" }
                TabButton { text: "Réglages" }
                onCurrentIndexChanged: {
                    if (currentIndex === 2) backend.refreshGenerations();
                    if (currentIndex === 3) backend.refreshRoutine();
                }
            }
            // Tout vérifier, à droite des onglets (chaque carte a aussi le
            // sien) ; la recherche en cours s'affiche dans le bandeau du bas.
            IconAction {
                visible: tabs.currentIndex === 0
                iconName: "view-refresh-symbolic"
                enabled: !backend.pendingBusy
                tooltip: "Tout vérifier (30 à 60 s) : configuration Nix, nouvelles versions en ligne, Flatpaks. Rien n'est modifié."
                    + (backend.pending.time ? "\nDernière recherche complète " + window.when(backend.pending.time) : "")
                onClicked: backend.refreshPending()
            }
            Button {
                visible: window.running
                icon.name: "process-stop"
                text: "Arrêter"
                onClicked: window.ask("Arrêter la mise à jour ?",
                    "L'étape en cours est interrompue. Une activation du système déjà lancée va quand même au bout.",
                    () => backend.stopRun())
            }
        }
    }

    // Ce qui tourne en ce moment, en bas de la fenêtre (le contenu ne bouge
    // pas) : un bandeau pour Nix (mise à jour, préparation, recherche), un
    // pour les Flatpaks, qui peuvent tourner en même temps. Pas dans l'onglet
    // En cours, qui en montre le détail.
    component StatusStrip: ToolBar {
        id: strip
        property string text
        property real progress: -1
        property bool showProgress: false
        position: ToolBar.Footer
        Layout.fillWidth: true
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            BusyIndicator {
                running: strip.visible
                implicitHeight: Kirigami.Units.iconSizes.small
                implicitWidth: implicitHeight
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: strip.text
            }
            ProgressBar {
                visible: strip.showProgress
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                from: 0; to: 1
                indeterminate: strip.progress < 0
                value: Math.max(0, strip.progress)
            }
            IconAction {
                iconName: "utilities-terminal-symbolic"
                tooltip: "Voir le détail et le journal (onglet En cours)"
                onClicked: window.showRunTab()
            }
        }
    }
    readonly property bool checking: backend.pendingBusy && !backend.pendingQuick
    readonly property bool flatpakBusy: backend.flatpakRun.active === true
        || (window.running && (backend.run.parts || []).some(p => p.id === "flatpak" && p.state === "running"))
    footer: ColumnLayout {
        spacing: 0
        visible: tabs.currentIndex !== 1
        StatusStrip {
            visible: window.running || backend.prebuildActive || (window.checking && backend.pendingPart !== "flatpak")
            showProgress: window.running || backend.prebuildActive
            progress: backend.progress
            text: window.running || backend.prebuildActive ? backend.summary
                : ({ system: "Vérification de la configuration système…",
                     home: "Vérification de la configuration utilisateur…",
                     config: "Vérification de la configuration…",
                     flake: "Recherche des mises à jour des entrées du flake…" }[backend.pendingPart]
                   || "Recherche de toutes les mises à jour…")
        }
        StatusStrip {
            visible: window.flatpakBusy || (window.checking && backend.pendingPart === "flatpak")
            showProgress: window.flatpakBusy
            text: window.flatpakBusy ? "Mise à jour des Flatpaks…" : "Recherche des mises à jour Flatpak…"
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        currentIndex: tabs.currentIndex
        PendingPage {}
        RunPage {}
        HistoryPage {}
        SettingsPage {}
    }
}
