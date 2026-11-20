import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol). Entrée adoptée : la ligne ouvre les changements
// sur GitHub (« i ») ; entrée en ligne : liens « Adopter » et « Changements »
// au survol.
RowLayout {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Bouton « mettre à jour cette entrée » (nouvelles versions en ligne).
    property bool updatable: false
    Layout.fillWidth: true

    // Entrée adoptée : toute la ligne ouvre les changements sur GitHub.
    // Entrée en ligne : deux liens au survol, « Adopter » et « Changements ».
    readonly property bool clickable: !row.updatable && row.url.length > 0
    HoverHandler {
        id: hover
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        enabled: row.clickable
        onTapped: Qt.openUrlExternally(row.url)
    }
    // Lien texte, visible au survol de la ligne (place gardée).
    component RowLink: Label {
        id: link
        signal activated()
        opacity: hover.hovered && enabled ? 1 : 0
        color: linkHover.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.linkColor
        font.underline: linkHover.hovered
        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: link.activated() }
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
        Layout.maximumWidth: Math.max(0, row.width - name.width - (row.updatable ? Kirigami.Units.gridUnit * 9 : Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing) - 4 * row.spacing)
        // Ligne survolée : tout le texte en couleur d'accent (cliquable).
        opacity: hover.hovered && row.clickable ? 1 : 0.8
        color: hover.hovered && row.clickable ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && hover.hovered
        ToolTip.text: row.label
    }
    IconAction {
        visible: !row.updatable
        iconName: "help-about-symbolic"
        // Au survol de la ligne seulement (place gardée), en couleur d'accent.
        opacity: row.clickable && hover.hovered ? 1 : 0
        enabled: row.clickable
        highlighted: hover.hovered
        tooltip: "Voir les changements sur GitHub"
        onClicked: Qt.openUrlExternally(row.url)
    }
    RowLink {
        visible: row.updatable
        enabled: !window.running
        Layout.leftMargin: Kirigami.Units.smallSpacing
        text: "Adopter"
        onActivated: backend.updateInput(row.input.name)
    }
    RowLink {
        visible: row.updatable
        enabled: row.url.length > 0
        text: "Changements"
        onActivated: Qt.openUrlExternally(row.url)
    }
    Item { Layout.fillWidth: true; Layout.preferredWidth: 0 }
}
