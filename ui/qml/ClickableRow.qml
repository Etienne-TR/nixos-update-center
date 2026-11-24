import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Ligne cliquable d'une liste (entrées du flake, Flatpaks, paquets,
// versions) : au survol, un fond léger sur toute la ligne, sans changer le
// pointeur ; un clic donne sa position (menu ouvert sous le curseur).
Item {
    id: cr
    default property alias content: row.data
    property bool clickable: true
    // Ligne choisie (liste à sélection) : fond teinté de la couleur
    // d'accent.
    property bool selected: false
    readonly property bool hovered: mouse.containsMouse
    // Hauteur commune à toutes les lignes de liste de l'interface.
    property real minimumHeight: Kirigami.Units.gridUnit * 1.6
    signal clicked(real x)
    Layout.fillWidth: true
    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight + Kirigami.Units.smallSpacing, minimumHeight)

    // Débord du fond de survol à gauche et à droite : le texte reste aligné
    // sur les titres, et le fond a sa marge autour du texte.
    readonly property real overflow: Kirigami.Units.largeSpacing
    Rectangle {
        x: -cr.overflow
        width: parent.width + 2 * cr.overflow
        height: parent.height
        radius: Kirigami.Units.cornerRadius
        color: cr.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
             : cr.clickable && mouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.07) : "transparent"
    }
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }
    // Par-dessus le contenu (z) et sur tout le fond : le survol et le clic
    // réagissent sur toute la ligne, pas seulement sur le texte. MouseArea
    // plutôt que HoverHandler / TapHandler : ces derniers reçoivent aussi
    // les clics et le survol à travers une fenêtre modale ouverte
    // par-dessus.
    MouseArea {
        id: mouse
        z: 1
        x: -cr.overflow
        width: parent.width + 2 * cr.overflow
        height: parent.height
        hoverEnabled: true
        onClicked: (m) => { if (cr.clickable) cr.clicked(m.x - cr.overflow); }
    }
}
