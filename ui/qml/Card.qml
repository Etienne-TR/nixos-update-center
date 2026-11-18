import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Bloc titré de la fenêtre.
Frame {
    id: card
    property string title
    property string subtitle
    // Pastille juste après le titre (état de la section).
    property string badge
    property color badgeColor: Kirigami.Theme.textColor
    default property alias content: inner.data
    // Boutons d'action, alignés à droite sur la ligne du titre.
    property alias actions: actionsRow.data
    Layout.fillWidth: true

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            visible: card.title.length > 0
            Label {
                text: card.title
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
            }
            Label {
                visible: card.badge.length > 0
                text: card.badge
                color: card.badgeColor
                font.bold: true
            }
            Label {
                Layout.fillWidth: true
                text: card.subtitle
                opacity: 0.7
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
            RowLayout {
                id: actionsRow
                spacing: Kirigami.Units.smallSpacing
            }
        }
        ColumnLayout {
            id: inner
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
