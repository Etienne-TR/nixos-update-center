import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Bouton divisé d'un seul tenant : un cadre arrondi, l'action principale à
// gauche, une flèche à droite (menu), séparées par un trait discret qui ne
// touche pas les bords. Survol : fond léger sur la partie visée seulement.
Rectangle {
    id: sb
    property string text
    property string iconName
    property string tooltip
    property string arrowTooltip
    // Flèche (menu) affichée ou non.
    property bool hasMenu: true
    // Entrées du menu : MenuEntry.
    default property alias menuItems: menu.contentData
    signal clicked()

    readonly property int pad: Kirigami.Units.smallSpacing
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    radius: Kirigami.Units.cornerRadius
    // À plat, comme FlatButton : fond teinté, sans bordure.
    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

    // Fond de survol d'une partie : un seul rectangle (une seule couche de
    // transparence, pas de zone plus foncée), arrondi côté extérieur et
    // coupé net côté intérieur, contre le trait de séparation.
    component Hover: Item {
        property bool shown
        property bool leftSide
        anchors.fill: parent
        visible: shown
        clip: true
        Rectangle {
            // Débord côté intérieur, masqué par clip : coins carrés là.
            width: parent.width + radius
            height: parent.height
            x: parent.leftSide ? 0 : -radius
            radius: sb.radius
            color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
        }
    }

    RowLayout {
        id: row
        spacing: 0
        AbstractButton {
            id: main
            hoverEnabled: true
            implicitWidth: mainRow.implicitWidth + 2 * Kirigami.Units.largeSpacing
            implicitHeight: mainRow.implicitHeight + 2 * sb.pad
            onClicked: sb.clicked()
            background: Hover { shown: main.hovered || main.pressed; leftSide: true }
            contentItem: Item {
                RowLayout {
                    id: mainRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        visible: sb.iconName.length > 0
                        source: sb.iconName
                        isMask: true
                        color: Kirigami.Theme.textColor
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: implicitWidth
                    }
                    Label { text: sb.text }
                }
            }
            ToolTip.visible: hovered && sb.tooltip.length > 0
            ToolTip.delay: 500
            ToolTip.text: sb.tooltip
        }
        // Séparateur discret.
        Rectangle {
            visible: sb.hasMenu
            implicitWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: sb.pad
            Layout.bottomMargin: sb.pad
            color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
        }
        AbstractButton {
            id: arrow
            visible: sb.hasMenu
            hoverEnabled: true
            implicitWidth: Kirigami.Units.iconSizes.small + 2 * sb.pad + 2
            implicitHeight: main.implicitHeight
            onClicked: menu.popup(sb, sb.width - menu.width, sb.height)
            background: Hover { shown: arrow.hovered || arrow.pressed || menu.visible; leftSide: false }
            contentItem: Item {
                Kirigami.Icon {
                    anchors.centerIn: parent
                    source: "pan-down-symbolic"
                    isMask: true
                    color: Kirigami.Theme.textColor
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                }
            }
            ToolTip.visible: hovered && sb.arrowTooltip.length > 0
            ToolTip.delay: 500
            ToolTip.text: sb.arrowTooltip
        }
    }
    LineMenu { id: menu }
}
