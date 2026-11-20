import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol). Pas d'icône : la ligne survolée passe en couleur
// d'accent, et un clic ouvre sous le curseur un menu de ses actions (Adopter
// pour une entrée en ligne, changements sur GitHub).
RowLayout {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Entrée en ligne : le menu propose aussi « Adopter ».
    property bool updatable: false
    Layout.fillWidth: true

    readonly property bool clickable: row.url.length > 0 || (row.updatable && !window.running)
    readonly property bool lit: hover.hovered && row.clickable

    HoverHandler {
        id: hover
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: row.clickable
        onTapped: (point) => menu.popup(row, point.position.x, row.height)
    }
    // Entrée de menu au rendu commun (même alignement pour toutes), avec une
    // icône facultative en fin de ligne.
    component RowMenuItem: MenuItem {
        id: item
        property string endIcon
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                text: item.text
                color: item.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                opacity: item.enabled ? 1 : 0.5
            }
            Kirigami.Icon {
                visible: item.endIcon.length > 0
                source: item.endIcon
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: implicitWidth
                isMask: true
                color: item.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
        }
    }
    Menu {
        id: menu
        RowMenuItem {
            visible: row.updatable
            height: visible ? implicitHeight : 0
            text: "Adopter"
            enabled: !window.running
            onTriggered: backend.updateInput(row.input.name)
        }
        // Comparaison entre les deux révisions (GitHub pour l'instant) ;
        // maillon : lien vers le navigateur.
        RowMenuItem {
            text: "Voir les changements"
            endIcon: "insert-link-symbolic"
            enabled: row.url.length > 0
            onTriggered: Qt.openUrlExternally(row.url)
        }
    }

    Label {
        id: name
        text: row.input.name
        color: row.lit ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    }
    Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        opacity: row.lit ? 1 : 0.8
        color: row.lit ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
}
