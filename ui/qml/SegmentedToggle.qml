import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Sélecteur segmenté (Qt Quick Controls et Kirigami n'en ont pas) : un fond
// arrondi légèrement teinté pour tout le groupe, et le segment actif posé
// dessus comme une « pastille » claire et arrondie qui glisse d'un choix à
// l'autre. Pas de séparateurs : rien à aligner entre segments.
Rectangle {
    id: seg
    // [{ text, value }]
    property var options: []
    property string value: options.length ? options[0].value : ""
    readonly property int pad: 3
    implicitWidth: row.implicitWidth + 2 * pad
    implicitHeight: row.implicitHeight + 2 * pad
    // Arrondi extérieur commun à toute l'appli (cornerRadius), pastille
    // concentrique à l'intérieur : rayon extérieur moins la marge.
    readonly property int innerRadius: Math.max(2, Math.round(Kirigami.Units.cornerRadius) - pad)
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

    // Pastille du segment actif.
    Rectangle {
        id: pill
        readonly property Item target: repeater.count > 0 ? repeater.itemAt(Math.max(0, seg.options.findIndex(o => o.value === seg.value))) : null
        x: target ? Math.round(row.x + target.x) : 0
        y: seg.pad
        width: target ? Math.round(target.width) : 0
        height: row.height
        radius: seg.innerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        Behavior on x { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        x: seg.pad
        y: seg.pad
        Repeater {
            id: repeater
            model: seg.options
            AbstractButton {
                id: b
                required property var modelData
                readonly property bool active: seg.value === modelData.value
                // Largeur du texte en demi-gras (actif) : rien ne bouge en
                // changeant de choix.
                TextMetrics { id: bold; text: b.modelData.text; font.family: label.font.family; font.pointSize: label.font.pointSize; font.weight: Font.DemiBold }
                implicitWidth: Math.round(bold.advanceWidth + 2 * Kirigami.Units.largeSpacing)
                implicitHeight: Math.round(label.implicitHeight + 2 * Kirigami.Units.smallSpacing)
                hoverEnabled: true
                onClicked: seg.value = modelData.value
                background: Item {}
                contentItem: Label {
                    id: label
                    text: b.modelData.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.weight: b.active ? Font.DemiBold : Font.Normal
                    color: Kirigami.Theme.textColor
                    opacity: b.active || b.hovered ? 1 : 0.7
                }
            }
        }
    }
}
