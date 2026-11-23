import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Versions installées : l'inventaire de ce qui tourne maintenant (système,
// utilisateur, chaque application Flatpak), une ligne chacun, rangé par date
// de la version actuelle (aujourd'hui, hier…). Un clic ouvre l'historique de
// l'élément, du plus récent au plus ancien, d'où l'on peut revenir à une
// version antérieure. La chronologie de tout ce qui a changé est dans le
// Journal.
ColumnLayout {
    id: page
    spacing: Kirigami.Units.smallSpacing

    readonly property var gens: backend.generations || {}

    // Type affiché : all, nix (système et utilisateur), flatpak.
    property string filter: "all"
    // Recherche textuelle (nom, identifiant, type), sans casse.
    property string search: ""

    // Toutes les versions, groupées par élément (clé : system, home ou ref
    // Flatpak), chaque groupe du plus récent au plus ancien.
    readonly property var groups: {
        const out = [];
        for (const g of (gens.system || []))
            // Même forme que les Flatpaks : nom, « version » (la
            // génération) en plus clair, étiquette du type.
            out.push({ key: "system", kind: "system", label: "Nix", title: "NixOS", version: "génération " + g.number,
                       time: g.time, current: g.current, number: g.number });
        for (const g of (gens.home || []))
            out.push({ key: "home", kind: "home", label: "Nix", title: "Home Manager", version: "génération " + g.number,
                       time: g.time, current: g.current, number: g.number });
        for (const f of (gens.flatpak || []))
            // Nom du menu d'applications (« Zen Browser ») ; l'identifiant
            // dans la fiche, ou seul pour une application désinstallée.
            out.push({ key: f.ref, kind: "flatpak", label: "Flatpak", title: f.name || f.app, install: f.operation === "deploy install",
                       detail: f.name ? f.app : "", version: f.version || "",
                       time: f.time, current: f.current, ref: f.ref, commit: f.commit });
        out.sort((a, b) => b.time - a.time);
        const groups = {};
        for (const it of out) (groups[it.key] = groups[it.key] || []).push(it);
        // Rang par rapport à l'actuelle : 0 actuelle, 1 la précédente… ;
        // -1 plus récente (après un retour arrière).
        for (const k in groups) {
            let r = -1;
            for (const it of groups[k]) {
                if (it.current) r = 0;
                it.rank = r < 0 ? -1 : r++;
            }
        }
        return groups;
    }

    // Inventaire : la version actuelle de chaque élément (les applications
    // désinstallées n'y sont plus).
    readonly property var items: {
        const q = page.search.trim().toLowerCase();
        const shown = [];
        for (const k in page.groups) {
            const cur = page.groups[k].find(it => it.current);
            if (!cur || (page.filter === "nix" && cur.kind === "flatpak") || (page.filter === "flatpak" && cur.kind !== "flatpak")) continue;
            if (q && !(cur.title + " " + (cur.detail || "") + " " + cur.label).toLowerCase().includes(q)) continue;
            shown.push(Object.assign({}, cur, {
                // Des versions plus récentes existent : on est revenu en
                // arrière.
                rolledBack: page.groups[k].some(it => it.rank < 0),
                count: page.groups[k].length,
                section: window.daySection(cur.time) }));
        }
        shown.sort((a, b) => b.time - a.time);
        return shown;
    }

    // Historique ouvert (clé d'un groupe), dans une fenêtre par-dessus.
    property string opened: ""

    // Barre de filtres : passe sur une deuxième ligne quand la fenêtre est
    // étroite, pour ne pas imposer de largeur minimale.
    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        // Recherche en premier, même allure que les sélecteurs (fond teinté,
        // arrondi concentrique, même hauteur).
        Kirigami.SearchField {
            id: searchField
            width: Kirigami.Units.gridUnit * 9
            height: typeToggle.implicitHeight
            placeholderText: "Rechercher…"
            onTextChanged: page.search = text
            background: Rectangle {
                radius: typeToggle.radius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                border.width: searchField.activeFocus ? 1 : 0
                border.color: Kirigami.Theme.highlightColor
            }
            // L'icône « search » de Kirigami manque au thème (qui affiche un
            // document à la place) : loupe de l'icône « edit-find ».
            Component.onCompleted: {
                for (const c of searchField.children)
                    if (c.source === "search") c.source = "edit-find-symbolic";
            }
        }
        SegmentedToggle {
            id: typeToggle
            // Nix : le système et l'utilisateur (une ligne chacun) ; mêmes
            // mots que les filtres du Journal.
            options: [ { text: "Tout", value: "all" }, { text: "Nix", value: "nix" }, { text: "Flatpak", value: "flatpak" } ]
            value: page.filter
            onValueChanged: page.filter = value
        }
    }
    Label {
        visible: page.items.length === 0
        text: page.search ? "Aucune version ne correspond à « " + page.search + " »." : "Aucune version trouvée."
        opacity: 0.7
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: page.items
        ScrollBar.vertical: ScrollBar {}
        section.property: "section"
        // Section courante collée en haut pendant le défilement.
        section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
        section.delegate: SectionHeader {}
        // Ligne cliquable : un clic ouvre l'historique de l'élément.
        delegate: ClickableRow {
            id: line
            required property var modelData
            readonly property var it: modelData
            width: ListView.view.width - Kirigami.Units.gridUnit
            x: Kirigami.Units.smallSpacing
            onClicked: page.opened = line.it.key
            Label { text: line.it.title }
            // Numéro de version (Flatpak), en plus clair.
            Label {
                visible: text.length > 0
                opacity: 0.7
                text: line.it.version || ""
            }
            Tag { text: line.it.label }
            Item { Layout.fillWidth: true }
            // Après un retour arrière : une version plus récente existe.
            Tag {
                visible: line.it.rolledBack
                text: "retour arrière"
                tinted: true
                tint: Kirigami.Theme.neutralTextColor
            }
            Label {
                // Date en bout de ligne, alignée à droite comme dans le
                // Journal.
                opacity: 0.7
                text: window.shortWhen(line.it.time)
            }
        }
    }

    // Historique d'un élément, dans une fenêtre : ses versions, de la plus
    // récente à la plus ancienne. Choisir une version ancienne active le
    // bouton du bas, qui y revient : la fenêtre sert aussi de confirmation.
    Dialog {
        id: history
        readonly property var versions: page.groups[page.opened] || []
        readonly property var cur: versions.find(it => it.current) || versions[0] || {}
        readonly property bool flat: cur.kind === "flatpak"
        // Version choisie (index), -1 : aucune.
        property int chosen: -1
        readonly property var pick: chosen >= 0 ? versions[chosen] : null
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        visible: page.opened.length > 0
        onOpened: chosen = -1
        onClosed: page.opened = ""
        width: Math.min(window.width - 40, Kirigami.Units.gridUnit * 30)
        height: Math.min(window.height - 40, implicitHeight)
        padding: Kirigami.Units.largeSpacing * 2
        topPadding: Kirigami.Units.largeSpacing
        header: ColumnLayout {
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: history.flat ? history.cur.title
                    : history.cur.kind === "system" ? "Générations NixOS" : "Générations Home Manager"
                font.weight: 650
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                padding: Kirigami.Units.largeSpacing * 2
                bottomPadding: 0
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                // Ce qui produit les générations : identifiant pour un Flatpak.
                text: history.flat ? (history.cur.detail || "")
                    : history.cur.kind === "system" ? "Configuration système" : "Configuration utilisateur"
                opacity: 0.7
                leftPadding: Kirigami.Units.largeSpacing * 2
                rightPadding: Kirigami.Units.largeSpacing * 2
                elide: Text.ElideRight
            }
        }
        contentItem: ListView {
            id: historyList
            implicitHeight: contentHeight
            clip: true
            model: history.versions
            ScrollBar.vertical: ScrollBar {}
            delegate: ClickableRow {
                id: hrow
                required property var modelData
                required property int index
                readonly property var it: modelData
                width: historyList.width - Kirigami.Units.gridUnit
                x: Kirigami.Units.smallSpacing
                // L'actuelle ne se choisit pas (rien à faire).
                clickable: !hrow.it.current
                selected: history.chosen === hrow.index
                onClicked: history.chosen = history.chosen === hrow.index ? -1 : hrow.index
                Label { text: hrow.it.kind === "flatpak" ? (hrow.it.version || "Version inconnue") : String(hrow.it.number) }
                Item { Layout.fillWidth: true }
                Tag {
                    visible: text.length > 0
                    text: hrow.it.current ? "actuelle" : hrow.it.rank < 0 ? "plus récente" : ""
                    tinted: hrow.it.current
                    tint: Kirigami.Theme.positiveTextColor
                }
                Label {
                    opacity: 0.7
                    text: window.when(hrow.it.time)
                }
            }
        }
        footer: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                visible: !history.pick
                opacity: 0.7
                text: "Choisis une version pour y revenir."
                elide: Text.ElideRight
            }
            Item { Layout.fillWidth: true; visible: !!history.pick }
            Button {
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                visible: !!history.pick
                text: !history.pick ? "" : history.flat
                    ? "Réinstaller " + (history.pick.version ? "la version " + history.pick.version : "cette version")
                    : "Réactiver la génération " + history.pick.number
                enabled: history.flat ? !(backend.flatpakRun.active === true) : !window.running
                onClicked: {
                    const it = history.pick;
                    history.close();
                    if (it.kind === "flatpak") backend.startFlatpakUpdate(["--commit", it.commit, it.ref]);
                    else backend.startUpdate([it.kind === "system" ? "--rollback-system" : "--rollback-home", String(it.number)]);
                }
            }
            Button {
                text: "Fermer"
                Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: history.close()
            }
        }
    }
}
