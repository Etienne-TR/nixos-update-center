import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol). Toute la ligne est cliquable : entrée adoptée,
// changements sur GitHub (« i ») ; entrée en ligne, menu (▾) avec Adopter et
// les changements.
RowLayout {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Bouton « mettre à jour cette entrée » (nouvelles versions en ligne).
    property bool updatable: false
    Layout.fillWidth: true

    // Ligne cliquable : un lien, ou le menu d'une entrée en ligne.
    readonly property bool clickable: row.url.length > 0 || (row.updatable && !window.running)
    // x : abscisse du clic dans la ligne (le menu s'ouvre sous le curseur),
    // sinon sous le ▾.
    function activate(x) {
        if (row.updatable) {
            if (x === undefined) menu.popup(arrow, 0, arrow.height);
            else menu.popup(row, x, row.height);
        }
        else if (row.url.length > 0) Qt.openUrlExternally(row.url);
    }
    HoverHandler {
        id: hover
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: row.clickable
        onTapped: (point) => row.activate(point.position.x)
    }
    Menu {
        id: menu
        MenuItem {
            text: "Adopter"
            icon.name: "media-playback-start-symbolic"
            enabled: !window.running
            onTriggered: backend.updateInput(row.input.name)
        }
        MenuItem {
            text: "Voir les changements sur GitHub"
            icon.name: "help-about-symbolic"
            enabled: row.url.length > 0
            onTriggered: Qt.openUrlExternally(row.url)
        }
    }

    Label {
        id: name
        text: row.input.name
        color: hover.hovered && row.clickable ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    }
    Label {
        id: detail
        // Pas plus large que son texte : les icônes le suivent.
        // Largeur de son texte, tronqué seulement si la ligne manque de place.
        Layout.maximumWidth: Math.max(0, row.width - name.width - 2 * (Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing) - 4 * row.spacing)
        // Ligne survolée : tout le texte en couleur d'accent (cliquable).
        opacity: hover.hovered && row.clickable ? 1 : 0.8
        color: hover.hovered && row.clickable ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
    IconAction {
        id: arrow
        iconName: row.updatable ? "pan-down-symbolic" : "help-about-symbolic"
        // Au survol de la ligne seulement (place gardée), en couleur d'accent.
        opacity: row.clickable && hover.hovered ? 1 : 0
        enabled: row.clickable
        highlighted: hover.hovered
        tooltip: row.updatable ? "Adopter, ou voir les changements sur GitHub" : "Voir les changements sur GitHub"
        onClicked: row.activate()
    }
    Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
}
