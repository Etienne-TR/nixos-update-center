import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Onglet à plat : l'onglet courant posé comme une pastille teintée (même
// langage que les sélecteurs), les autres en texte seul, plus clair.
TabButton {
    id: t
    hoverEnabled: true
    width: implicitWidth
    padding: Kirigami.Units.smallSpacing
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    TextMetrics { id: bold; text: t.text; font.family: label.font.family; font.pointSize: label.font.pointSize; font.weight: Font.DemiBold }
    implicitWidth: Math.round(bold.advanceWidth) + leftPadding + rightPadding
    implicitHeight: label.implicitHeight + topPadding + bottomPadding
    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: t.checked ? Qt.alpha(Kirigami.Theme.textColor, 0.10)
             : t.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.05) : "transparent"
        border.width: t.visualFocus ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
    }
    contentItem: Label {
        id: label
        text: t.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.weight: t.checked ? Font.DemiBold : Font.Normal
        opacity: t.checked || t.hovered ? 1 : 0.7
    }
}
