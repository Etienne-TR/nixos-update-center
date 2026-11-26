import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Barre de défilement à plat : une poignée arrondie teintée, sans flèches
// ni rail ; plus épaisse et plus foncée au survol ou à l'appui.
// Construite sur le modèle nu (Templates), pas sur la barre du style.
T.ScrollBar {
    id: sb
    hoverEnabled: true
    padding: 2
    minimumSize: 0.1
    // Masquée quand tout tient à l'écran.
    policy: T.ScrollBar.AsNeeded
    // Invisible (et sans place réservée par la vue) quand tout tient ;
    // size vaut aussi 0 tant que la vue n'est pas mise en page (ou qu'elle
    // ne défile pas dans ce sens) : sinon un point restait dans le coin.
    visible: size > 0 && size < 1
    readonly property real thickness: sb.hovered || sb.pressed ? Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing * 1.5
    implicitWidth: Kirigami.Units.smallSpacing * 2 + leftPadding + rightPadding
    implicitHeight: Kirigami.Units.smallSpacing * 2 + topPadding + bottomPadding
    contentItem: Rectangle {
        implicitWidth: sb.thickness
        implicitHeight: sb.thickness
        radius: Math.min(width, height) / 2
        color: Qt.alpha(Kirigami.Theme.textColor, sb.pressed ? 0.45 : sb.hovered ? 0.35 : 0.22)
        opacity: sb.size < 1 ? 1 : 0
    }
    background: Item {}
}
