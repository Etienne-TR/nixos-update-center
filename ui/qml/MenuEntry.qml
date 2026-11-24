import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Entrée des menus de ligne (entrées du flake, Flatpaks, paquets) : même
// alignement pour toutes, marges égales, hauteur compacte, survol discret.
MenuItem {
    id: item
    // Marges égales à gauche et à droite, survol discret (fond teinté,
    // texte inchangé).
    leftPadding: Kirigami.Units.largeSpacing * 1.5
    rightPadding: Kirigami.Units.largeSpacing * 1.5
    topPadding: Kirigami.Units.smallSpacing * 1.5
    bottomPadding: Kirigami.Units.smallSpacing * 1.5
    // Hauteur du texte et des marges, sans le minimum du style : plus
    // compact.
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    // Centré verticalement : le style impose une hauteur minimale d'entrée,
    // plus grande que texte + marges (sinon le texte reste en haut).
    contentItem: Label {
        verticalAlignment: Text.AlignVCenter
        text: item.text
        color: Kirigami.Theme.textColor
        opacity: item.enabled ? 1 : 0.5
    }
    // Fond de survol en retrait du bord du menu.
    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.smallSpacing
            anchors.rightMargin: Kirigami.Units.smallSpacing
            anchors.topMargin: 2
            anchors.bottomMargin: 2
            radius: window.cornerRadius
            color: item.highlighted && item.enabled ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18) : "transparent"
        }
    }
}
