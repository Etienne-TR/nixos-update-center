import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol) et, au survol de la ligne, un bouton vers les
// changements sur GitHub.
RowLayout {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Bouton « mettre à jour cette entrée » (nouvelles versions en ligne).
    property bool updatable: false
    Layout.fillWidth: true

    HoverHandler { id: hover }

    Label {
        text: row.input.name
        font.bold: true
    }
    Label {
        id: detail
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        opacity: 0.8
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
    IconAction {
        iconName: "software-update-available-symbolic"
        visible: row.updatable
        opacity: hover.hovered ? 1 : 0
        enabled: !window.running
        tooltip: "update --flake-input " + row.input.name + " : nix flake update " + row.input.name
                 + " seule, avec commit de flake.lock. Elle passe ensuite dans « Entrées du flake », à appliquer."
        onClicked: backend.updateInput(row.input.name)
    }
    IconAction {
        iconName: "help-about-symbolic"
        // Place gardée : la ligne ne bouge pas quand l'icône apparaît.
        opacity: row.url.length > 0 && hover.hovered ? 1 : 0
        enabled: row.url.length > 0
        tooltip: "Voir les changements sur GitHub"
        onClicked: Qt.openUrlExternally(row.url)
    }
}
