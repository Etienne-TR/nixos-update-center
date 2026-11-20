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
    // Entrée de menu au rendu commun (même alignement pour toutes).
    component RowMenuItem: MenuItem {
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
                radius: Kirigami.Units.cornerRadius
                color: item.highlighted && item.enabled ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18) : "transparent"
            }
        }
    }
    Menu {
        id: menu
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        // Largeur ajustée au texte le plus long (sinon largeur minimale du
        // style, avec de la place vide à droite).
        width: {
            let w = 0;
            for (let i = 0; i < count; ++i) {
                const it = itemAt(i);
                if (it && it.visible) w = Math.max(w, it.contentItem.implicitWidth + it.leftPadding + it.rightPadding);
            }
            return w + leftPadding + rightPadding;
        }
        RowMenuItem {
            visible: row.updatable
            height: visible ? implicitHeight : 0
            text: "Adopter l'entrée"
            enabled: !window.running
            onTriggered: backend.updateInput(row.input.name)
        }
        // Comparaison entre les deux révisions (GitHub pour l'instant) ;
        // ↗ : lien vers le navigateur.
        RowMenuItem {
            text: "Voir les changements ↗"
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
