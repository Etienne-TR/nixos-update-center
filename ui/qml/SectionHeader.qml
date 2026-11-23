import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Titre de section d'une liste par date (Journal, Versions) : centré, sur le
// fond de la fenêtre pour rester lisible quand il reste collé en haut
// pendant le défilement.
Rectangle {
    required property string section
    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: label.implicitHeight + Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    color: Kirigami.Theme.backgroundColor
    Label {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        text: parent.section
        font.weight: 650
        opacity: 0.8
    }
}
