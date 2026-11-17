import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Avancement d'une partie de la mise à jour en cours, affiché dans sa
// section de l'onglet En attente.
ColumnLayout {
    id: root
    // Partie : system, home, flatpak ou flake.
    property string partId
    readonly property var run: backend.run
    readonly property var part: run.active ? (run.parts || []).find(p => p.id === root.partId) : undefined
    readonly property string partState: part ? part.state : ""
    readonly property var build: backend.build
    readonly property real fraction: {
        const b = build.builds || {}, d = build.downloads || {};
        const expected = (b.expected || 0) + (d.expected || 0);
        return expected > 0 ? Math.min(1, ((b.done || 0) + (b.failed || 0) + (d.done || 0)) / expected) : -1;
    }
    visible: partState === "running" || partState === "pending"
    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        BusyIndicator {
            visible: root.partState === "running"
            running: visible
            implicitHeight: Kirigami.Units.iconSizes.small
            implicitWidth: implicitHeight
        }
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.bold: true
            text: root.partState === "pending" ? "En attente de son tour…" : (root.run.step || "En cours…")
        }
        Button {
            flat: true
            icon.name: "utilities-terminal"
            text: "Journal"
            onClicked: window.showRunTab()
        }
    }
    ProgressBar {
        visible: root.partState === "running"
        Layout.fillWidth: true
        from: 0; to: 1
        indeterminate: root.fraction < 0
        value: Math.max(0, root.fraction)
    }
    Label {
        visible: root.partState === "running" && (root.build.building || []).length > 0
        Layout.fillWidth: true
        elide: Text.ElideRight
        opacity: 0.8
        text: "Construction : " + (root.build.building || []).map(b => b.name).slice(0, 3).join(", ")
    }
    Label {
        visible: root.partState === "running" && !!root.run.progress
        opacity: 0.8
        text: root.run.progress ? root.run.progress.label + " : " + backend.formatBytes(root.run.progress.bytes) + " téléchargés" : ""
    }
}
