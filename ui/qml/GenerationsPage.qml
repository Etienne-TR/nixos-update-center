import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Versions installées, en une seule liste chronologique par sections
// (aujourd'hui, hier, cette semaine…) : générations du système et de Home
// Manager, versions des applications Flatpak. Une étiquette dit de quoi il
// s'agit ; un clic propose d'y revenir.
ColumnLayout {
    id: page
    spacing: Kirigami.Units.smallSpacing

    readonly property var gens: backend.generations || {}


    // Type affiché : all, system, home, flatpak.
    property string filter: "all"
    // État : all, current (actuelles), previous (la précédente de chacune).
    property string stateFilter: "all"
    readonly property var items: {
        const out = [];
        for (const g of (gens.system || []))
            out.push({ kind: "system", label: "Système", title: "Génération n° " + g.number,
                       time: g.time, current: g.current, number: g.number });
        for (const g of (gens.home || []))
            out.push({ kind: "home", label: "Utilisateur", title: "Génération n° " + g.number,
                       time: g.time, current: g.current, number: g.number });
        for (const f of (gens.flatpak || []))
            out.push({ kind: "flatpak", label: "Flatpak", title: f.app + (f.operation === "deploy install" ? " (installation)" : ""),
                       time: f.time, current: f.current, ref: f.ref, commit: f.commit });
        out.sort((a, b) => b.time - a.time);
        // Précédente : pour le système, l'utilisateur et chaque application,
        // la version juste avant l'actuelle (celle d'un retour arrière).
        const seen = {};
        for (const it of out) {
            const key = it.kind === "flatpak" ? it.ref : it.kind;
            if (it.current) seen[key] = "current";
            else if (seen[key] === "current") { it.previous = true; seen[key] = "done"; }
        }
        const shown = out.filter(it => (page.filter === "all" || it.kind === page.filter)
            && (page.stateFilter === "all" || (page.stateFilter === "current" ? it.current : !!it.previous)));
        for (const it of shown) it.section = window.daySection(it.time);
        return shown;
    }

    function revert(it) {
        const what = it.kind === "flatpak" ? it.title + " à cette version"
                   : (it.kind === "system" ? "au système" : "à l'utilisateur") + " de la génération " + it.number;
        window.ask("Revenir " + what + " ?",
            it.kind === "flatpak"
                ? "L'application revient à la version installée " + window.when(it.time) + ". Une prochaine mise à jour des Flatpaks la remettra à jour."
                : "Cette génération est réactivée. Une prochaine mise à jour reviendra à la configuration actuelle.",
            () => it.kind === "flatpak" ? backend.startFlatpakUpdate(["--commit", it.commit, it.ref])
                : backend.startUpdate([it.kind === "system" ? "--rollback-system" : "--rollback-home", String(it.number)]));
    }

    RowLayout {
        Layout.fillWidth: true
        SegmentedToggle {
            options: [ { text: "Tout", value: "all" }, { text: "Système", value: "system" },
                       { text: "Utilisateur", value: "home" }, { text: "Flatpak", value: "flatpak" } ]
            value: page.filter
            onValueChanged: page.filter = value
        }
        Item { implicitWidth: Kirigami.Units.largeSpacing }
        SegmentedToggle {
            options: [ { text: "Tout", value: "all" }, { text: "Actuelles", value: "current" },
                       { text: "Précédentes", value: "previous" } ]
            value: page.stateFilter
            onValueChanged: page.stateFilter = value
        }
        Item { Layout.fillWidth: true }
    }
    Label {
        visible: page.items.length === 0
        text: "Aucune version trouvée."
        opacity: 0.7
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: page.items
        ScrollBar.vertical: ScrollBar {}
        section.property: "section"
        section.delegate: Label {
            required property string section
            topPadding: Kirigami.Units.largeSpacing
            bottomPadding: Kirigami.Units.smallSpacing
            leftPadding: Kirigami.Units.smallSpacing
            text: section
            font.weight: 650
        }
        delegate: ItemDelegate {
            id: line
            required property var modelData
            readonly property var it: modelData
            width: ListView.view.width
            rightPadding: Kirigami.Units.gridUnit
            hoverEnabled: true
            onClicked: menu.popup()
            LineMenu {
                id: menu
                MenuEntry {
                    text: line.it.kind === "flatpak" ? "Revenir à cette version" : "Revenir à cette génération"
                    enabled: !line.it.current && (line.it.kind === "flatpak" ? !(backend.flatpakRun.active === true) : !window.running)
                    onTriggered: page.revert(line.it)
                }
            }
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Label {
                    text: line.it.title
                    color: line.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }
                // Étiquettes : de quoi il s'agit, et « actuelle ».
                Tag { text: line.it.label }
                Tag {
                    visible: line.it.current
                    text: "actuelle"
                    tinted: true
                    tint: Kirigami.Theme.positiveTextColor
                }
                Item { Layout.fillWidth: true }
                Label {
                    opacity: 0.7
                    text: window.shortWhen(line.it.time)
                }
            }
        }
    }
}
