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

    // À l'ouverture de la fenêtre : recherche des mises à jour si la
    // dernière date de plus de 5 minutes (pas au démarrage de la session,
    // où l'app est cachée).
    onVisibleChanged: {
        if (!visible || backend.pendingBusy) return;
        const t = backend.pending.time || 0;
        if (Date.now() / 1000 - t > 300) backend.refreshPending();
    }

    // Fermer la fenêtre la cache : l'icône reste dans le tray.
    onClosing: (close) => { close.accepted = false; window.hide(); }

    readonly property bool running: backend.run.active === true
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
                ToolTip.text: "Système, Home Manager et Flatpaks, sans toucher au flake. Une partie déjà à jour est sautée."
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

    // Mode développement (ui/dev.sh) : bandeau pour ne pas confondre avec
    // l'interface installée.
    property string devDir: ""
    footer: Kirigami.InlineMessage {
        visible: window.devDir.length > 0
        type: Kirigami.MessageType.Warning
        position: Kirigami.InlineMessage.Position.Footer
        text: "Version de développement : QML lu dans " + window.devDir + ", rechargé à chaque modification."
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
