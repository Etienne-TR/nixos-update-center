import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Texte à chasse fixe défilant (journal, différences de paquets).
ScrollView {
    id: root
    property alias text: area.text
    // Suivre la fin du texte tant qu'on est en bas.
    property bool follow: false
    Layout.fillWidth: true
    clip: true

    TextArea {
        id: area
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.NoWrap
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
        background: Rectangle {
            color: Kirigami.Theme.alternateBackgroundColor
            radius: Kirigami.Units.cornerRadius
        }
        onTextChanged: {
            if (root.follow && atEnd)
                Qt.callLater(() => { area.cursorPosition = area.length; });
        }
        property bool atEnd: true
    }

    ScrollBar.vertical.onPositionChanged: {
        const sb = ScrollBar.vertical;
        area.atEnd = sb.position + sb.size >= 0.98;
    }
}
