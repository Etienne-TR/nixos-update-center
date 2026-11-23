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
    LineMenu {
        id: menu
        MenuEntry {
            visible: row.updatable
            height: visible ? implicitHeight : 0
            text: "Adopter l'entrée"
            enabled: !window.running
            onTriggered: backend.updateInput(row.input.name)
        }
        // Comparaison entre les deux révisions (GitHub pour l'instant) ;
        // ↗ : lien vers le navigateur.
        MenuEntry {
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
        opacity: row.lit ? 1 : 0.7  // même retrait que les dates des fichiers
        color: row.lit ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
}
