import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ApplicationWindow {
    id: window
    // Marge unique de la fenêtre : autour des onglets et autour du contenu
    // des onglets, la même partout.
    readonly property real margin: Kirigami.Units.largeSpacing * 1.5
    // Arrondi unique des éléments (cartes, boutons, onglets, champs,
    // sélecteurs, lignes survolées) ; les pastilles intérieures des
    // sélecteurs sont concentriques (cet arrondi moins leur marge).
    readonly property int cornerRadius: Math.round(Kirigami.Units.cornerRadius)
    // Dimensions communes des fenêtres par-dessus les onglets : petites
    // (fiche, confirmation) et grandes (listes, journaux).
    readonly property real smallDialogWidth: Math.min(width - 2 * Kirigami.Units.gridUnit, Kirigami.Units.gridUnit * 26)
    readonly property real largeDialogWidth: Math.min(width - 2 * Kirigami.Units.gridUnit, Kirigami.Units.gridUnit * 40)
    readonly property real largeDialogHeight: height - 2 * Kirigami.Units.gridUnit
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

    // Ordre des onglets : 0 Mises à jour, 1 Versions installées, 2 Journal,
    // 3 Planification.
    readonly property int journalTab: 2
    function showRunTab() { tabs.currentIndex = window.journalTab; journalPage.openRunning(); }


    // Confirmation avant une action lourde (arrêt, retour arrière).
    // Titre court, détails dessous, bouton de confirmation qui dit l'action ;
    // pas de croix (Échap ou Annuler).
    Dialog {
        id: confirm
        property var action
        property alias message: confirmText.text
        property string confirmLabel: "Confirmer"
        // Position verticale fixe (haut à hauteur constante), quelle que
        // soit la hauteur du contenu : la fenêtre ne saute pas d'une fiche
        // à l'autre.
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.22)
        modal: true
        width: window.smallDialogWidth
        padding: Kirigami.Units.largeSpacing * 2
        header: Label {
            text: confirm.title
            font.weight: 650
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            padding: Kirigami.Units.largeSpacing * 2
            bottomPadding: 0
        }
        contentItem: Label {
            id: confirmText
            wrapMode: Text.WordWrap
        }
        // Ordre des boutons de toute l'appli : Annuler / Fermer d'abord,
        // l'action principale tout à droite.
        footer: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            FlatButton {
                text: "Annuler"
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: confirm.reject()
            }
            FlatButton {
                text: confirm.confirmLabel
                highlighted: true
                Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: confirm.accept()
            }
        }
        onAccepted: action()
    }
    // Fiche d'une ligne (entrée du flake, Flatpak, version) : titre, infos,
    // et ses actions en bas (Fermer en dernier). Remplace les menus de ligne.
    Dialog {
        id: info
        property alias message: infoText.text
        property var actions: []
        // Position verticale fixe (haut à hauteur constante), quelle que
        // soit la hauteur du contenu : la fenêtre ne saute pas d'une fiche
        // à l'autre.
        x: Math.round((parent.width - width) / 2)
        y: Math.round(parent.height * 0.22)
        modal: true
        width: window.smallDialogWidth
        padding: Kirigami.Units.largeSpacing * 2
        header: Label {
            text: info.title
            font.weight: 650
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            padding: Kirigami.Units.largeSpacing * 2
            bottomPadding: 0
            elide: Text.ElideRight
        }
        contentItem: Label {
            id: infoText
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }
        footer: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true; Layout.leftMargin: Kirigami.Units.largeSpacing * 2 }
            // « Fermer » d'abord, les actions ensuite, la principale (la
            // dernière) tout à droite.
            FlatButton {
                text: "Fermer"
                Layout.rightMargin: info.actions.length > 0 ? 0 : Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: info.close()
            }
            Repeater {
                model: info.actions
                FlatButton {
                    required property var modelData
                    required property int index
                    Layout.rightMargin: index === info.actions.length - 1 ? Kirigami.Units.largeSpacing * 2 : 0
                    Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                    text: modelData.text
                    // Action principale (main) : icône et teinte d'accent.
                    icon.name: modelData.icon || ""
                    highlighted: modelData.main === true
                    enabled: modelData.enabled !== false
                    onClicked: { info.close(); modelData.run(); }
                }
            }
        }
    }
    function showInfo(title, message, actions) {
        info.title = title;
        info.message = message;
        info.actions = actions || [];
        info.open();
    }

    function ask(title, message, action, confirmLabel) {
        confirm.title = title;
        confirm.message = message;
        confirm.action = action;
        confirm.confirmLabel = confirmLabel || "Confirmer";
        confirm.open();
    }

    // Journal d'une exécution passée.
    Dialog {
        id: logViewer
        property alias text: logText.text
        anchors.centerIn: parent
        modal: true
        width: window.largeDialogWidth
        height: window.largeDialogHeight
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            FlatButton {
                text: "Fermer"
                Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: logViewer.close()
            }
        }
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
        // Côtés : la marge de la fenêtre ; haut et bas plus serrés, la barre
        // reste basse.
        leftPadding: window.margin
        rightPadding: window.margin
        topPadding: Kirigami.Units.smallSpacing * 1.5
        bottomPadding: Kirigami.Units.smallSpacing * 1.5
        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            TabBar {
                id: tabs
                Layout.fillWidth: true
                // Onglets à plat (FlatTab) : pas de fond ni de ligne du style.
                background: Item {}
                // Onglets espacés : le style ignore « spacing », d'où une
                // rangée à nous.
                contentItem: ListView {
                    model: tabs.contentModel
                    currentIndex: tabs.currentIndex
                    orientation: ListView.Horizontal
                    spacing: Kirigami.Units.smallSpacing
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds
                    implicitHeight: contentItem.childrenRect.height
                }
                FlatTab {
                    text: backend.pendingCount > 0 ? "Mises à jour ●" : "Mises à jour ✓"
                }
                FlatTab { text: "Versions installées" }
                FlatTab { text: window.running ? "Journal ●" : "Journal" }
                FlatTab { text: "Planification" }
                onCurrentIndexChanged: {
                    if (currentIndex === 1 || currentIndex === 2) backend.refreshGenerations();
                    if (currentIndex === 3) backend.refreshRoutine();
                }
            }
            // Tout vérifier, à droite des onglets (chaque carte a aussi le
            // sien) ; la recherche en cours s'affiche dans le bandeau du bas.
            IconAction {
                visible: tabs.currentIndex === 0
                // Aligné sur les flèches des cartes : retrait intérieur des
                // cartes (la marge de la fenêtre est commune).
                Layout.rightMargin: Kirigami.Units.largeSpacing * 2 + 1
                iconName: "view-refresh-symbolic"
                // pendingParts lu : liaison réévaluée (checking() est du C++).
                enabled: backend.pendingParts.length >= 0 && !backend.checking("all")
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
                // Bascule de vitesse : grisée en priorité minimale, en couleur
                // d'accent à pleine vitesse ; un clic change de mode.
                IconAction {
                    visible: strip.kind === "prebuild"
                    // Profils d'énergie d'Adwaita (hérités par Pop) : économie
                    // = priorité minimale, performance = pleine vitesse.
                    iconName: backend.prebuild.boosted === true ? "power-profile-performance-symbolic" : "power-profile-power-saver-symbolic"
                    fallbackName: "media-seek-forward-symbolic"
                    highlighted: backend.prebuild.boosted === true
                    tooltip: backend.prebuild.boosted === true
                        ? "Pleine vitesse : cliquer pour revenir en priorité minimale"
                        : "Priorité minimale : cliquer pour passer à pleine vitesse"
                    onClicked: backend.boostPrebuild(backend.prebuild.boosted !== true)
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
                            window.ask("Arrêt de la mise à jour",
                                "L'étape en cours est interrompue, et la mise à jour utilisateur qui suit n'aura pas lieu. Une activation du système déjà lancée va quand même au bout.",
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
                    onClicked: { tabs.currentIndex = window.journalTab; journalPage.opened = strip.taskId; }
                }
                IconAction {
                    iconName: strip.expanded ? "go-down-symbolic" : "go-up-symbolic"
                    tooltip: strip.expanded ? "Replier" : "Afficher le terminal"
                    onClicked: window.expandedStrip = strip.expanded ? "" : strip.taskId
                }
            }
        }
    }
    // Nom d'une action, le même partout (bandeaux, Journal) : « Action
    // (domaine) » ; l'adoption dit « dans le flake ». id : identifiant de
    // la partie ; label : son libellé du moteur (« Flake (a b) »…).
    function actionTitle(id, label) {
        const one = /\((.*)\)$/.exec(label || "");
        switch (id) {
        case "prebuild": return "Préparation (Nix)";
        case "flatpak_download": return "Préparation (Flatpak)";
        case "system": return "Mise à jour système (NixOS)";
        case "home": return "Mise à jour utilisateur (Home Manager)";
        case "flake": return one ? "Adoption de " + one[1].split(" ").join(", ") + " dans le flake" : "Adoption de toutes les entrées du flake";
        case "flatpak": return (one ? "Mise à jour de " + one[1].split(", ").map(window.flatpakName).join(", ") : "Mise à jour") + " (Flatpak)";
        case "rollback_system": case "rollback_home": {
            // Numéro de la génération, à la fin du libellé du moteur.
            const n = /(\d+)$/.exec(label || "");
            return "Retour à " + (n ? "la génération " : "une génération ")
                + (id === "rollback_system" ? "système " : "utilisateur ") + (n ? n[1] + " " : "")
                + (id === "rollback_system" ? "(NixOS)" : "(Home Manager)");
        }
        case "check:config": case "check:system": case "check:home": return "Vérification de la configuration (Nix)";
        case "check:flake": return "Recherche (flake)";
        case "check:nix": return "Recherche (Nix)";
        case "check:flatpak": return "Recherche (Flatpak)";
        default: return "";
        }
    }
    // Nom affiché d'une application Flatpak (celui du lanceur, « Pods »)
    // d'après son identifiant ; l'identifiant s'il est inconnu.
    function flatpakName(id) {
        const f = ((backend.generations || {}).flatpak || []).find(x => x.app === id && x.name);
        return f ? f.name : id;
    }
    function stripLabel(t) {
        const id = t.part ? t.part.id : t.id === "flatpak" ? ((backend.flatpakRun.parts || [])[0] || {}).id || "flatpak" : t.id;
        const label = (t.part || (backend.flatpakRun.parts || [])[0] || {}).label || "";
        return actionTitle(id, label) || t.title || id;
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
        visible: tabs.currentIndex !== window.journalTab
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
                text: window.stripLabel(modelData)
                      + (paused ? " · En pause"
                         : modelData.state === "pending" ? " · En attente"
                         : modelData.detail ? " · " + modelData.detail : "")
                busy: active && !paused
                stoppable: active
                showProgress: active
                progress: modelData.id === "prebuild" ? (backend.prebuild.fraction >= 0 ? backend.prebuild.fraction : -1)
                        : modelData.id.startsWith("run:") ? window.buildFraction : -1
            }
        }
        Repeater {
            // Recherches : un bandeau par recherche Nix en cours (une
            // seconde attend la fin de la première, mais se voit), plus
            // Flatpak.
            model: window.nixChecks.map(k => ({ id: "check:" + k, title:
                        // Le nom de la carte concernée, pour s'y retrouver.
                        ({ system: "Vérification : Configuration Nix (système)", home: "Vérification : Configuration Nix (utilisateur)",
                           config: "Vérification : Configuration Nix", flake: "Recherche : Mise à jour du flake",
                           nix: "Recherche : Configuration Nix et Mise à jour du flake" }[k]
                         || "Recherche : Configuration Nix et Mise à jour du flake") }))
                   .concat(backend.pendingParts.includes("flatpak") ? [{ id: "check:flatpak", title: "Recherche : Flatpaks" }] : [])
            StatusStrip {
                required property var modelData
                taskId: modelData.id
                kind: "check"
                inJournal: false
                text: window.stripLabel(modelData) + "…"
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        // Marge de la fenêtre ; en haut, celle de la barre d'onglets suffit.
        anchors.margins: window.margin
        anchors.topMargin: window.margin
        currentIndex: tabs.currentIndex
        PendingPage {}
        GenerationsPage {}
        JournalPage { id: journalPage }
        SettingsPage {}
    }
}
