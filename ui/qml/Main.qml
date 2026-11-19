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
            Button {
                visible: !window.running
                highlighted: true
                icon.name: "system-software-update"
                text: "Tout appliquer"
                ToolTip.visible: hovered
                ToolTip.text: "update --system --home --flatpak : système, Home Manager et Flatpaks, sans toucher au flake. Une partie dont la génération évaluée est déjà installée est sautée ; push des commits, nh clean après un vrai switch."
                onClicked: backend.startUpdate(["--system", "--home", "--flatpak"])
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
