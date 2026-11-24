import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Bouton à plat de l'appli, même langage que les sélecteurs : fond teinté
// arrondi, sans bordure ni dégradé ; plus foncé au survol et à l'appui.
// highlighted : action principale, teintée de la couleur d'accent.
Button {
    id: b
    hoverEnabled: true
    padding: Kirigami.Units.smallSpacing
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    implicitWidth: Math.max(implicitContentWidth + leftPadding + rightPadding, Kirigami.Units.gridUnit * 4)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    readonly property color base: b.highlighted ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    background: Rectangle {
        radius: window.cornerRadius
        color: Qt.alpha(b.base, !b.enabled ? 0.05
                              : b.down ? (b.highlighted ? 0.40 : 0.18)
                              : b.hovered ? (b.highlighted ? 0.32 : 0.13)
                              : (b.highlighted ? 0.25 : 0.08))
        // Focus clavier : contour d'accent.
        border.width: b.visualFocus ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
    }
    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Item { Layout.fillWidth: true }
        Kirigami.Icon {
            visible: b.icon.name.length > 0
            source: b.icon.name
            isMask: true
            color: label.color
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
        }
        Label {
            id: label
            text: b.text
            color: b.enabled ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
        }
        Item { Layout.fillWidth: true }
    }
}
