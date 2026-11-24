import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Texte à chasse fixe défilant (journal, différences de paquets).
// TextEdit dans un Flickable plutôt qu'un TextArea : remplacer le texte d'un
// TextArea remet le curseur au début et fait remonter la vue. Ici, la
// position est gardée ; avec `follow`, la vue suit la fin du texte tant
// qu'on y est.
Rectangle {
    id: root
    property alias text: edit.text
    property bool follow: false
    // Vue en bas du texte (avant l'arrivée du nouveau contenu).
    property bool atEnd: true
    Layout.fillWidth: true
    // Fond neutre des vues (pas la couleur « alternée » du thème, teintée).
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false
    color: Kirigami.Theme.backgroundColor
    border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
    radius: Kirigami.Units.cornerRadius
    clip: true

    ScrollView {
        anchors.fill: parent
        ScrollBar.vertical: FlatScrollBar {}
        ScrollBar.horizontal: FlatScrollBar {}

        Flickable {
            id: flick
            contentWidth: edit.paintedWidth + 2 * edit.padding
            contentHeight: edit.paintedHeight + 2 * edit.padding
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: root.atEnd = contentY + height >= contentHeight - 8

            TextEdit {
                id: edit
                padding: Kirigami.Units.smallSpacing
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.NoWrap
                color: Kirigami.Theme.textColor
                selectionColor: Kirigami.Theme.highlightColor
                selectedTextColor: Kirigami.Theme.highlightedTextColor
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
                onTextChanged: {
                    if (root.follow && root.atEnd)
                        Qt.callLater(() => { flick.contentY = Math.max(0, flick.contentHeight - flick.height); });
                }
            }
        }
    }
}
