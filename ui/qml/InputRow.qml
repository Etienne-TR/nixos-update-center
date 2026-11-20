import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol). Toute la ligne est cliquable (changements sur
// GitHub) ; les icônes suivent le texte et apparaissent au survol.
RowLayout {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Bouton « mettre à jour cette entrée » (nouvelles versions en ligne).
    property bool updatable: false
    Layout.fillWidth: true

    HoverHandler {
        id: hover
        cursorShape: row.url.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: row.url.length > 0
        onTapped: Qt.openUrlExternally(row.url)
    }

    Label {
        id: name
        text: row.input.name
        color: hover.hovered && row.url.length > 0 ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    }
    Label {
        id: detail
        // Pas plus large que son texte : les icônes le suivent.
        // Largeur de son texte, tronqué seulement si la ligne manque de place.
        Layout.maximumWidth: Math.max(0, row.width - name.width - 2 * (Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing) - 4 * row.spacing)
        opacity: 0.8
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
    IconAction {
        iconName: "media-playback-start-symbolic"
        visible: row.updatable && !window.running
        opacity: hover.hovered ? 1 : 0
        tooltip: "Adopter la nouvelle version de cette entrée dans flake.lock (update --flake-input " + row.input.name + " : nix flake update " + row.input.name
                 + ", avec commit). Elle passe ensuite dans « Entrées du flake », à appliquer."
        onClicked: backend.updateInput(row.input.name)
    }
    IconAction {
        iconName: "help-about-symbolic"
        // Place gardée : la ligne ne bouge pas quand l'icône apparaît.
        opacity: row.url.length > 0 && hover.hovered ? 1 : 0
        enabled: row.url.length > 0
        tooltip: "Voir les changements sur GitHub"
        onClicked: Qt.openUrlExternally(row.url)
    }
    Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
}
