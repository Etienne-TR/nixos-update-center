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
    ToolButton {
        icon.name: "internet-web-browser"
        // Place gardée : la ligne ne bouge pas quand le bouton apparaît.
        opacity: row.url.length > 0 && hover.hovered ? 1 : 0
        enabled: row.url.length > 0
        implicitHeight: detail.implicitHeight + Kirigami.Units.smallSpacing
        implicitWidth: implicitHeight
        display: AbstractButton.IconOnly
        onClicked: Qt.openUrlExternally(row.url)
        ToolTip.visible: hovered
        ToolTip.text: "Voir les changements sur GitHub"
    }
}
