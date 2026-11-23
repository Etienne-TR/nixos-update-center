import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Une entrée du flake : nom, versions ou dates (tronquées si trop longues,
// texte complet au survol). Ligne cliquable (fond léger au survol) : un clic
// ouvre sa fiche, avec ses actions en bas (Adopter pour une entrée en ligne,
// changements sur GitHub).
ClickableRow {
    id: row
    required property var input
    property string label: ""
    property string url: ""
    // Entrée en ligne : le menu propose aussi « Adopter ».
    property bool updatable: false
    // Cliquable seulement s'il y a une action (lien, adoption).
    clickable: row.url.length > 0 || row.updatable
    // Fiche de l'entrée : versions, commits, révisions, et ses actions.
    onClicked: {
        const i = row.input, short = r => r ? r.slice(0, 12) : "?";
        const lines = [row.label];
        if (i.from && i.from.rev) lines.push("Révision : " + short(i.from.rev) + " → " + short(i.to.rev));
        else if (i.to && i.to.rev) lines.push("Révision : " + short(i.to.rev));
        if (i.to && i.to.owner) lines.push("Dépôt : " + i.to.owner + "/" + i.to.repo);
        const actions = [];
        if (row.updatable) actions.push({ text: "Adopter l'entrée", enabled: !window.running, run: () => backend.updateInput(i.name) });
        if (row.url.length > 0) actions.push({ text: "Voir les changements ↗", run: () => Qt.openUrlExternally(row.url) });
        window.showInfo(i.name, lines.filter(x => x).join("\n"), actions);
    }

    Label {
        id: name
        text: row.input.name
    }
    Label {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        opacity: 0.7  // même retrait que les dates des fichiers
        elide: Text.ElideMiddle
        text: row.label
        ToolTip.visible: truncated && row.hovered
        ToolTip.text: row.label
    }
}
