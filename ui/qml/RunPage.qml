import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Exécution en cours (ou dernière) : parties, étape, avancement, journal.
ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing
    readonly property var run: backend.run
    readonly property var build: backend.build
    readonly property real buildFraction: {
        const b = build.builds || {}, d = build.downloads || {};
        const expected = (b.expected || 0) + (d.expected || 0);
        return expected > 0 ? Math.min(1, ((b.done || 0) + (b.failed || 0) + (d.done || 0)) / expected) : -1;
    }

    Card {
        title: window.runTitle(page.run.active ? "running" : page.run.state)
        subtitle: page.run.started ? "lancée " + backend.formatTime(page.run.started) : ""

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
            visible: page.run.active && page.build.phase !== undefined
            Layout.fillWidth: true
            from: 0; to: 1
            indeterminate: page.buildFraction < 0
            value: Math.max(0, page.buildFraction)
        }
        Label {
            visible: page.run.active && (page.build.building || []).length > 0
            text: "Construction : " + (page.build.building || []).map(b => b.name).slice(0, 3).join(", ")
            Layout.fillWidth: true
            elide: Text.ElideRight
            opacity: 0.8
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
