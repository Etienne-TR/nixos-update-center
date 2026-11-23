import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Avancement d'une partie de la mise à jour en cours, affiché dans sa
// section de l'onglet Mises à jour.
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

    // Partie pas encore commencée : une simple mention.
    Label {
        visible: root.partState === "pending"
        text: "En attente des parties précédentes"
        opacity: 0.6
    }
    // Partie en cours : étape et accès au journal.
    RowLayout {
        visible: root.partState === "running"
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.run.step || "En cours…"
        }
        IconAction {
            iconName: "utilities-terminal-symbolic"
            tooltip: "Voir le journal (onglet En cours)"
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
