import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Sélecteur à choix multiples, même allure que SegmentedToggle : un fond
// arrondi teinté pour tout le groupe, sans espace entre les segments, et une
// pastille claire sous chaque segment choisi.
Rectangle {
    id: seg
    // [{ text, value, tooltip }]
    property var options: []
    // Valeurs choisies.
    property var values: []
    signal toggled(var values)
    readonly property int pad: 3
    implicitWidth: row.implicitWidth + 2 * pad
    implicitHeight: row.implicitHeight + 2 * pad
    // Arrondi extérieur commun à toute l'appli (cornerRadius), pastille
    // concentrique à l'intérieur : rayon extérieur moins la marge.
    readonly property int innerRadius: Math.max(2, Math.round(Kirigami.Units.cornerRadius) - pad)
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

    Row {
        id: row
        x: seg.pad
        y: seg.pad
        Repeater {
            model: seg.options
            AbstractButton {
                id: b
                required property var modelData
                readonly property bool active: seg.values.includes(modelData.value)
                TextMetrics { id: bold; text: b.modelData.text; font.family: label.font.family; font.pointSize: label.font.pointSize; font.weight: Font.DemiBold }
                implicitWidth: Math.round(bold.advanceWidth + 2 * Kirigami.Units.largeSpacing)
                implicitHeight: Math.round(label.implicitHeight + 2 * Kirigami.Units.smallSpacing)
                hoverEnabled: true
                onClicked: {
                    const v = b.modelData.value;
                    seg.toggled(b.active ? seg.values.filter(x => x !== v) : seg.values.concat([v]));
                }
                background: Rectangle {
                    visible: b.active
                    radius: seg.innerRadius
                    color: Kirigami.Theme.backgroundColor
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                }
                contentItem: Label {
                    id: label
                    text: b.modelData.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.weight: b.active ? Font.DemiBold : Font.Normal
                    color: Kirigami.Theme.textColor
                    opacity: b.active || b.hovered ? 1 : 0.7
                }
                ToolTip.visible: hovered && !!b.modelData.tooltip
                ToolTip.delay: 500
                ToolTip.text: b.modelData.tooltip || ""
            }
        }
    }
}
