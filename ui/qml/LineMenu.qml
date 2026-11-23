import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Menu d'une ligne cliquable (entrée du flake, Flatpak, paquets), ouvert sous
// le curseur ; ses entrées sont des MenuEntry.
Menu {
    id: menu
    topPadding: Kirigami.Units.smallSpacing
    bottomPadding: Kirigami.Units.smallSpacing
    // Largeur ajustée au texte le plus long (sinon largeur minimale du style,
    // avec de la place vide à droite).
    width: {
        let w = 0;
        for (let i = 0; i < count; ++i) {
            const it = itemAt(i);
            if (it && it.visible) w = Math.max(w, it.contentItem.implicitWidth + it.leftPadding + it.rightPadding);
        }
        return w + leftPadding + rightPadding;
    }
}
