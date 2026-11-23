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
    onVisibleChanged: if (visible) backend.refreshPending(true)
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: window.visible
        onTriggered: backend.refreshPending(true)
    }

    // Échap : replie le bandeau déplié.
    Shortcut { sequence: "Escape"; enabled: window.expandedStrip.length > 0; onActivated: window.expandedStrip = "" }

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
    // Section d'une liste par date (Journal, Versions).
    function daySection(time) {
        const d = new Date(time * 1000), now = new Date(window.now);
        const day = t => new Date(t.getFullYear(), t.getMonth(), t.getDate()).getTime();
        const days = Math.round((day(now) - day(d)) / 86400000);
        if (days <= 0) return "Aujourd'hui";
        if (days === 1) return "Hier";
        if (days < 7) return "Cette semaine";
        if (days < 31) return "Ce mois-ci";
        return "Plus ancien";
    }
    // Date courte dans une section : l'heure seule pour aujourd'hui et hier.
    function shortWhen(time) {
        const s = daySection(time);
        return s === "Aujourd'hui" || s === "Hier"
            ? new Date(time * 1000).toLocaleTimeString(Qt.locale("fr_FR"), "HH:mm") : when(time);
    }
    // Onglet imposé pour les captures de test.
    property int testTab: -1
    onTestTabChanged: if (testTab >= 0) tabs.currentIndex = testTab

    // Couleurs d'état, communes aux pages.
    function stateColor(state) {
        switch (state) {
        case "success": return Kirigami.Theme.positiveTextColor;
        case "failed": case "interrupted": return Kirigami.Theme.negativeTextColor;
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

    function showRunTab() { tabs.currentIndex = 1; journalPage.openRunning(); }


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
                    text: backend.pendingCount > 0 ? "Mises à jour ●" : "Mises à jour"
                }
                TabButton { text: window.running ? "Journal ●" : "Journal" }
                TabButton { text: "Versions" }
                TabButton { text: "Réglages" }
                onCurrentIndexChanged: {
                    if (currentIndex === 1 || currentIndex === 2) backend.refreshGenerations();
                    if (currentIndex === 3) backend.refreshRoutine();
                }
            }
            // Tout vérifier, à droite des onglets (chaque carte a aussi le
            // sien) ; la recherche en cours s'affiche dans le bandeau du bas.
            IconAction {
                visible: tabs.currentIndex === 0
                // Aligné sur les flèches des cartes (marge de la page et des
                // cartes).
                Layout.rightMargin: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
                iconName: "view-refresh-symbolic"
                enabled: !backend.checking("all")
                tooltip: "Tout vérifier (30 à 60 s) : configuration Nix, nouvelles versions en ligne, Flatpaks. Rien n'est modifié."
                    + (backend.pending.time ? "\nDernière recherche complète " + window.when(backend.pending.time) : "")
                onClicked: backend.refreshPending()
            }
        }
    }

    // Ce qui tourne en ce moment, en bas de la fenêtre (le contenu ne bouge
    // pas) : un bandeau pour Nix (mise à jour, préparation, recherche), un
    // pour les Flatpaks, qui peuvent tourner en même temps. Pas dans l'onglet
    // Journal, qui en montre le détail.
    // Bandeau d'une action en cours : une ligne (état, avancement, boutons
    // selon l'action) ; un clic la déplie vers le haut avec son terminal en
    // direct, sans quitter l'onglet.
    property string expandedStrip: ""
    component StatusStrip: ToolBar {
        id: strip
        property string taskId
        property string kind        // run, prebuild, flatpak, check
        property bool busy: true
        // Arrêtable (une action en attente ne l'est pas, une en pause oui).
        property bool stoppable: true
        property string text
        property real progress: -1
        property bool showProgress: false
        property bool inJournal: true
        readonly property bool expanded: window.expandedStrip === taskId && taskId.length > 0
        position: ToolBar.Footer
        Layout.fillWidth: true
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        // Terminal de l'action, relu chaque seconde quand le bandeau est
        // déplié.
        property string log: ""
        function readLog() {
            if (kind === "check") log = backend.checkLog;
            else if (kind === "prebuild") { backend.refreshPrebuildLog(); log = backend.prebuildLog; }
            else {
                const path = kind === "flatpak" ? (backend.flatpakRun.log || "")
                           : (((backend.run.parts || []).find(p => "run:" + p.id === taskId)) || {}).log || "";
                log = path ? backend.readLog(path).split("\n").map(l => l.split("\r").pop()).join("\n") : "";
            }
        }
        Timer {
            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: strip.expanded && window.visible
            onTriggered: strip.readLog()
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            MonoText {
                visible: strip.expanded
                Layout.fillWidth: true
                Layout.preferredHeight: window.height * 0.4
                follow: true
                text: strip.log.length > 0 ? strip.log : "…"
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                BusyIndicator {
                    opacity: strip.busy ? 1 : 0
                    running: strip.visible && strip.busy
                    implicitHeight: Kirigami.Units.iconSizes.small
                    implicitWidth: implicitHeight
                }
                // Le texte : clic pour déplier ou replier.
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: strip.text
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: window.expandedStrip = strip.expanded ? "" : strip.taskId }
                }
                ProgressBar {
                    visible: strip.showProgress
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    from: 0; to: 1
                    indeterminate: strip.progress < 0
                    value: Math.max(0, strip.progress)
                }
                // Actions selon le type.
                IconAction {
                    visible: strip.kind === "prebuild" && !backend.prebuild.boosted
                    iconName: "media-seek-forward"
                    tooltip: "Passer à pleine vitesse (la construction tourne en priorité minimale)"
                    onClicked: backend.boostPrebuild()
                }
                IconAction {
                    visible: strip.kind === "prebuild"
                    iconName: backend.prebuild.paused ? "media-playback-start-symbolic" : "media-playback-pause-symbolic"
                    tooltip: backend.prebuild.paused ? "Reprendre la construction" : "Mettre la construction en pause"
                    onClicked: backend.pausePrebuild(!backend.prebuild.paused)
                }
                IconAction {
                    visible: strip.kind === "flatpak"
                    iconName: backend.flatpakPaused ? "media-playback-start-symbolic" : "media-playback-pause-symbolic"
                    tooltip: backend.flatpakPaused ? "Reprendre" : "Mettre en pause"
                    onClicked: backend.pauseFlatpak(!backend.flatpakPaused)
                }
                IconAction {
                    visible: strip.stoppable
                    iconName: "process-stop-symbolic"
                    tooltip: strip.kind === "run" ? "Arrêter la mise à jour (système et utilisateur)" : "Arrêter"
                    onClicked: {
                        if (strip.kind === "run")
                            window.ask("Arrêter la mise à jour ?",
                                "L'étape en cours est interrompue. Une activation du système déjà lancée va quand même au bout.",
                                () => backend.stopRun());
                        else if (strip.kind === "prebuild") backend.stopPrebuild();
                        else if (strip.kind === "flatpak") backend.stopFlatpak();
                        else backend.stopCheck(strip.taskId.replace(/^check:/, ""));
                    }
                }
                IconAction {
                    visible: strip.inJournal
                    iconName: "view-list-details-symbolic"
                    fallbackName: "view-list-text"
                    tooltip: "Voir dans le Journal"
                    onClicked: { tabs.currentIndex = 1; journalPage.opened = strip.taskId; }
                }
                IconAction {
                    iconName: strip.expanded ? "go-down-symbolic" : "go-up-symbolic"
                    tooltip: strip.expanded ? "Replier" : "Afficher le terminal"
                    onClicked: window.expandedStrip = strip.expanded ? "" : strip.taskId
                }
            }
        }
    }
    // Avancement de la construction pendant une mise à jour.
    readonly property real buildFraction: {
        const b = backend.build.builds || {}, d = backend.build.downloads || {};
        const expected = (b.expected || 0) + (d.expected || 0);
        return expected > 0 ? Math.min(1, ((b.done || 0) + (b.failed || 0) + (d.done || 0)) / expected) : -1;
    }
    // Vérifications en cours (hors rapide) : Nix d'un côté, Flatpak de l'autre.
    readonly property var nixChecks: backend.pendingParts.filter(p => p !== "quick" && p !== "flatpak")
    readonly property bool checking: nixChecks.length > 0
    readonly property bool flatpakBusy: backend.flatpakRun.active === true
        || (window.running && (backend.run.parts || []).some(p => p.id === "flatpak" && p.state === "running"))
    footer: ColumnLayout {
        spacing: 0
        visible: tabs.currentIndex !== 1
        // Un bandeau par action en cours : celles du Journal (une mise à
        // jour complète : une action par partie), plus les recherches.
        Repeater {
            model: journalPage.runningTasks
            StatusStrip {
                required property var modelData
                readonly property bool active: modelData.state === "running"
                taskId: modelData.id
                kind: modelData.id.startsWith("run:") ? "run" : modelData.id
                opacity: active ? 1 : 0.6
                readonly property bool paused: (modelData.id === "prebuild" && backend.prebuild.paused === true)
                                             || (modelData.id === "flatpak" && backend.flatpakPaused)
                text: modelData.title
                      + (paused ? " · en pause"
                         : modelData.state === "pending" ? " · en attente"
                         : modelData.detail ? " · " + modelData.detail : "")
                busy: active && !paused
                stoppable: active
                showProgress: active
                progress: modelData.id === "prebuild" ? (backend.prebuild.fraction >= 0 ? backend.prebuild.fraction : -1)
                        : modelData.id.startsWith("run:") ? window.buildFraction : -1
            }
        }
        Repeater {
            // Recherches : Nix (une à la fois affichée) et Flatpak.
            model: (window.checking ? [{ id: "check:" + window.nixChecks[0], title:
                        ({ system: "Vérification du système", home: "Vérification de l'utilisateur",
                           config: "Vérification de la configuration", flake: "Recherche des nouvelles versions du flake" }[window.nixChecks[0]]
                         || "Recherche des mises à jour") }] : [])
                   .concat(backend.pendingParts.includes("flatpak") ? [{ id: "check:flatpak", title: "Recherche des mises à jour Flatpak" }] : [])
            StatusStrip {
                required property var modelData
                taskId: modelData.id
                kind: "check"
                inJournal: false
                text: modelData.title + "…"
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        currentIndex: tabs.currentIndex
        PendingPage {}
        JournalPage { id: journalPage }
        GenerationsPage {}
        SettingsPage {}
    }
}
