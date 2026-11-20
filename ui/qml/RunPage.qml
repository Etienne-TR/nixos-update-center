import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami

// Tâches en cours ou récentes : la mise à jour (unité <nom>-run), la
// préparation en arrière-plan (service <nom>-prebuild) et la recherche des
// mises à jour. Liste à gauche, détail de la tâche choisie à droite.
ColumnLayout {
    id: page
    spacing: Kirigami.Units.smallSpacing

    // Largeur de la liste et liste masquée ou non, gardées d'une fois sur
    // l'autre.
    Settings {
        id: layoutSettings
        category: "runPage"
        property real listWidth: Kirigami.Units.gridUnit * 15
        property bool listHidden: false
    }

    readonly property var run: backend.run
    readonly property var pre: backend.prebuild
    readonly property var result: backend.prebuildResult
    readonly property var fp: backend.flatpakRun
    // Journal des Flatpaks : celui de l'exécution en parallèle, sinon celui
    // de la dernière mise à jour seule.
    readonly property string fpLog: run.active && run.flatpakLog ? run.flatpakLog : (fp.log || "")
    readonly property var tasks: {
        const t = [];
        if (window.checking)
            t.push({ id: "check", title: "Recherche des mises à jour", state: "running", detail: "en cours" });
        t.push({ id: "run", title: "Mise à jour",
                 state: run.active ? "running" : (run.state || ""),
                 detail: run.active ? (run.step || "en cours")
                       : run.started ? window.runTitle(run.state).replace("Mise à jour ", "") + ", " + window.when(run.finished || run.started)
                       : "aucune" });
        // Flatpaks en parallèle de la mise à jour : tâche à part, avec son
        // journal.
        // ou lancée seule (flatpak.json).
        if (run.active && run.flatpakLog)
            t.push({ id: "flatpak", title: "Mise à jour des Flatpaks", state: "running", detail: "en parallèle" });
        else if (fp.state)
            t.push({ id: "flatpak", title: "Mise à jour des Flatpaks",
                     state: fp.active ? "running" : fp.state,
                     detail: fp.active ? "en cours"
                           : ({success: "terminée", failed: "en échec", stopped: "arrêtée"}[fp.state] || fp.state) + ", " + window.when(fp.finished || fp.started) });
        t.push({ id: "prebuild", title: "Préparation en arrière-plan",
                 state: backend.prebuildActive ? "running" : (result.state || ""),
                 detail: backend.prebuildActive ? (pre.fraction >= 0 ? Math.round(pre.fraction * 100) + " %" : "évaluation")
                       : result.state ? ({success: "terminée", failed: "incomplète", stopped: "arrêtée"}[result.state] || result.state)
                                        + ", " + window.when(result.time)
                       : "aucune" });
        // Ce qui tourne d'abord.
        return t.filter(x => x.state === "running").concat(t.filter(x => x.state !== "running"));
    }
    // En-tête du détail : titre et sous-titre.
    component DetailHeader: RowLayout {
        property string title
        property string subtitle
        Layout.fillWidth: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2
        Label {
            text: parent.title
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }
        Label {
            Layout.fillWidth: true
            text: parent.subtitle
            opacity: 0.7
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
    }

    property string selected: ""
    readonly property string current: selected.length > 0 && tasks.some(t => t.id === selected) ? selected : tasks[0].id

    // Bouton de la liste des tâches, toujours à la même place (comme
    // l'application Claude) : liste affichée, il est en tête de la liste
    // (la séparation descend alors depuis le haut) ; liste masquée, dans
    // cette barre au-dessus du détail.
    component ListToggle: IconAction {
        iconName: "sidebar-show-symbolic"
        tooltip: layoutSettings.listHidden ? "Afficher la liste des tâches" : "Masquer la liste des tâches"
        onClicked: layoutSettings.listHidden = !layoutSettings.listHidden
    }
    RowLayout {
        visible: layoutSettings.listHidden
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 2
        ListToggle {}
        Item { Layout.fillWidth: true }
    }

    SplitView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        orientation: Qt.Horizontal
        // Séparation : un simple trait vertical, sur toute la hauteur.
        handle: Item {
            implicitWidth: Kirigami.Units.largeSpacing
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 1
                height: parent.height
                color: Qt.alpha(Kirigami.Theme.textColor, SplitHandle.hovered || SplitHandle.pressed ? 0.4 : 0.15)
            }
        }

        // Liste des tâches.
        Item {
            id: taskList
            visible: !layoutSettings.listHidden
            SplitView.preferredWidth: layoutSettings.listWidth
            SplitView.minimumWidth: Kirigami.Units.gridUnit * 8
            SplitView.maximumWidth: page.width / 2
            // Largeur choisie en tirant la séparation, gardée.
            SplitView.onPreferredWidthChanged: layoutSettings.listWidth = SplitView.preferredWidth
            RowLayout {
                id: listHeader
                anchors.left: parent.left
                anchors.right: parent.right
                height: Kirigami.Units.gridUnit * 2
                ListToggle {}
                Item { Layout.fillWidth: true }
            }
            ListView {
                anchors.top: listHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true
                model: page.tasks
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    highlighted: modelData.id === page.current
                    onClicked: page.selected = modelData.id
                    contentItem: RowLayout {
                        Label {
                            text: window.stateGlyph(modelData.state === "partial" ? "failed" : modelData.state)
                            color: window.stateColor(modelData.state)
                            font.bold: true
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Label { text: modelData.title; font.bold: modelData.state === "running"; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: modelData.detail; opacity: 0.7; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        // Détail de la tâche choisie.
        StackLayout {
            SplitView.fillWidth: true
            currentIndex: page.current === "prebuild" ? 1 : page.current === "check" ? 2 : page.current === "flatpak" ? 3 : 0

            // Mise à jour : parties, étape, avancement, journal.
            ColumnLayout {
                id: runDetail
                spacing: Kirigami.Units.largeSpacing
                readonly property var build: backend.build
                readonly property real buildFraction: {
                    const b = build.builds || {}, d = build.downloads || {};
                    const expected = (b.expected || 0) + (d.expected || 0);
                    return expected > 0 ? Math.min(1, ((b.done || 0) + (b.failed || 0) + (d.done || 0)) / expected) : -1;
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    id: runCard
                    DetailHeader {
                        title: window.runTitle(page.run.active ? "running" : page.run.state)
                        subtitle: page.run.started ? "lancée " + window.when(page.run.started) : ""
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Repeater {
                            model: page.run.parts || []
                            Label {
                                required property var modelData
                                text: window.stateGlyph(modelData.state) + " " + modelData.label
                                color: window.stateColor(modelData.state)
                                font.bold: modelData.state === "running"
                            }
                        }
                    }
                    Label {
                        visible: page.run.active && !!page.run.step
                        text: page.run.step || ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    ProgressBar {
                        visible: page.run.active && runDetail.build.phase !== undefined
                        Layout.fillWidth: true
                        from: 0; to: 1
                        indeterminate: runDetail.buildFraction < 0
                        value: Math.max(0, runDetail.buildFraction)
                    }
                    Label {
                        visible: page.run.active && !!page.run.progress
                        text: page.run.progress ? page.run.progress.label + " : " + backend.formatBytes(page.run.progress.bytes) + " téléchargés" : ""
                    }
                    Repeater {
                        model: page.run.notes || []
                        Label {
                            required property var modelData
                            text: modelData
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: backend.log.length > 0 ? backend.log : "Le journal de la mise à jour s'affichera ici."
                }
            }

            // Préparation : avancement de Nix et Flatpak, journal du service.
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    DetailHeader {
                        title: backend.prebuildActive ? "Préparation en cours" : "Préparation en arrière-plan"
                        subtitle: backend.prebuildActive ? (page.pre.boosted ? "à pleine vitesse" : "priorité minimale")
                                : page.result.time ? window.when(page.result.time) : ""
                    }
                    ProgressBar {
                        visible: backend.prebuildActive
                        Layout.fillWidth: true
                        from: 0; to: 1
                        indeterminate: !(page.pre.fraction >= 0)
                        value: page.pre.fraction >= 0 ? page.pre.fraction : 0
                    }
                    Label {
                        visible: backend.prebuildActive && page.pre.phase !== "eval"
                        text: "Constructions : " + (page.pre.builds ? page.pre.builds.done + "/" + page.pre.builds.expected : "–")
                              + "    Téléchargements : " + (page.pre.downloads ? page.pre.downloads.done + "/" + page.pre.downloads.expected : "–")
                    }
                    Label {
                        visible: backend.prebuildActive && (page.pre.building || []).length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.8
                        text: "Construction : " + (page.pre.building || []).map(b => b.name).slice(0, 3).join(", ")
                    }
                    Label {
                        visible: backend.prebuildActive && !!page.pre.flatpak
                        text: page.pre.flatpak === "running" ? "Flatpak : téléchargement en cours"
                            : page.pre.flatpak === "done" ? "Flatpak : téléchargé" : "Flatpak : en échec"
                    }
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: backend.prebuildLog.length > 0 ? backend.prebuildLog : "Le journal de la préparation s'affichera ici."
                }
                // Journal relu toutes les 2 s tant qu'il est affiché.
                Timer {
                    interval: 2000
                    repeat: true
                    triggeredOnStart: true
                    running: window.visible && page.visible && page.current === "prebuild"
                    onTriggered: backend.refreshPrebuildLog()
                }
            }

            // Recherche des mises à jour : courte, sans journal.
            ColumnLayout {
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    DetailHeader {
                        title: "Recherche des mises à jour"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Évaluation de la config, nouvelles versions des entrées et Flatpaks. Le résultat s'affiche dans l'onglet En attente."
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // Flatpaks en parallèle : leur journal, relu chaque seconde (il
            // rejoint celui de la mise à jour une fois terminés).
            ColumnLayout {
                id: flatpakDetail
                spacing: Kirigami.Units.largeSpacing
                property string log: ""
                DetailHeader {
                    title: "Mise à jour des Flatpaks"
                    subtitle: page.run.active && page.run.flatpakLog ? "en parallèle de la mise à jour"
                            : page.fp.active ? "en cours" : page.fp.started ? "lancée " + window.when(page.fp.started) : ""
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: flatpakDetail.log.length > 0 ? flatpakDetail.log : "Le journal des Flatpaks s'affichera ici."
                }
                Timer {
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    running: window.visible && page.visible && page.current === "flatpak" && page.fpLog.length > 0
                    // Barres de progression (\r) : seul leur dernier état.
                    onTriggered: flatpakDetail.log = backend.readLog(page.fpLog)
                        .split("\n").map(l => l.split("\r").pop()).join("\n")
                }
            }
        }
    }
}
