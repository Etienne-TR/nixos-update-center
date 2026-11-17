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

    function selectedParts() {
        const parts = [];
        if (systemBox.checked) parts.push("--system");
        if (homeBox.checked) parts.push("--home");
        if (flatpakBox.checked) parts.push("--flatpak");
        return parts;
    }

    Connections {
        target: backend
        function onRunStarted() { tabs.currentIndex = 1; }
    }

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
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                ColumnLayout {
                    spacing: 0
                    Label {
                        text: backend.title
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                    }
                    Label {
                        text: backend.summary
                        opacity: 0.8
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    visible: !window.running
                    icon.name: "download"
                    text: "Mettre à jour le flake"
                    enabled: !backend.prebuildActive
                    ToolTip.visible: hovered
                    ToolTip.text: "Lance la routine : nix flake update (commit de flake.lock, envoyé après une application réussie), préparation en arrière-plan, notification. Rien n'est installé."
                    onClicked: backend.checkUpdates()
                }
                Button {
                    visible: !window.running
                    highlighted: true
                    icon.name: "system-software-update"
                    text: "Appliquer"
                    enabled: window.selectedParts().length > 0
                    ToolTip.visible: hovered
                    ToolTip.text: "Reconstruit et active la config telle qu'elle est (parties cochées), sans toucher au flake. Une partie déjà à jour est sautée."
                    onClicked: backend.startUpdate(window.selectedParts())
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
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                enabled: !window.running
                CheckBox { id: systemBox; text: "Système"; checked: true }
                CheckBox { id: homeBox; text: "Home Manager"; checked: true }
                CheckBox { id: flatpakBox; text: "Flatpak"; checked: true }
            }
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
