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

    // Fond de survol, débordant un peu à gauche et à droite : le texte reste
    // aligné sur les titres.
    Rectangle {
        x: -Kirigami.Units.smallSpacing
        width: parent.width + 2 * Kirigami.Units.smallSpacing
        height: parent.height
        radius: Kirigami.Units.cornerRadius
        color: cr.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.25)
             : cr.clickable && mouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.07) : "transparent"
    }
    // MouseArea plutôt que HoverHandler / TapHandler : ces derniers
    // reçoivent aussi les clics et le survol à travers une fenêtre modale
    // ouverte par-dessus (un clic dans la fenêtre cliquait la liste dessous).
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: (m) => { if (cr.clickable) cr.clicked(m.x); }
    }
    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }
}
