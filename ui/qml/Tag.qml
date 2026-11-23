import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Étiquette compacte à la suite d'un nom : type (Système, Flatpak…), état
// (terminée, en échec…), « actuelle ». Couleur facultative (sinon neutre).
Label {
    id: tag
    property color tint: Kirigami.Theme.textColor
    property bool tinted: false
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    leftPadding: Kirigami.Units.smallSpacing
    rightPadding: Kirigami.Units.smallSpacing
    color: tinted ? tint : Kirigami.Theme.textColor
    background: Rectangle {
        radius: Kirigami.Units.cornerRadius
        color: Qt.alpha(tag.tinted ? tag.tint : Kirigami.Theme.textColor, tag.tinted ? 0.12 : 0.08)
    }
}
