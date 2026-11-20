import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Petite action en icône seule, sans fond : seule la couleur de l'icône
// change au survol.
Item {
    id: root
    property string iconName
    // Icône de repli si le thème n'a pas la première (Breeze / Adwaita).
    property string fallbackName
    // Couleur de survol imposée (ligne cliquable survolée).
    property bool highlighted: false
    property string tooltip
    signal clicked()
    implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
    implicitHeight: implicitWidth

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small
        height: width
        source: root.iconName
        fallback: root.fallbackName.length > 0 ? root.fallbackName : "unknown"
        isMask: true
        color: !root.enabled ? Kirigami.Theme.disabledTextColor
             : mouse.containsMouse || root.highlighted ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    ToolTip.visible: mouse.containsMouse && tooltip.length > 0
    ToolTip.text: tooltip
}
