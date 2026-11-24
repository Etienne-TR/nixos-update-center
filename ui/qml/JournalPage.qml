import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Journal : tout ce qui tourne ou a tourné (mises à jour, Flatpaks,
// préparation, recherche), le plus récent en haut et ce qui tourne d'abord.
// Liste à gauche, détail à droite : en direct pour une action en cours,
// journal complet et générations activées pour une action passée.
ColumnLayout {
    id: page
    spacing: Kirigami.Units.smallSpacing


    readonly property var run: backend.run
    readonly property var pre: backend.prebuild
    readonly property var result: backend.prebuildResult
    readonly property var fp: backend.flatpakRun
    // Journal de la dernière mise à jour des Flatpaks (unité à part).
    readonly property string fpLog: fp.log || ""
    // Titre d'une partie (une action) d'après son identifiant.
    function partTitle(p) {
        return window.actionTitle(p.id, p.label) || p.label || p.id;
    }
    // Titre d'une exécution d'après ses parties.
    function entryTitle(h) {
        const parts = h.parts || [];
        if (parts.length === 0) return "Mise à jour";
        // Une partie : une action (exécutions récentes) ; plusieurs :
        // ancienne exécution d'un seul tenant.
        if (parts.length === 1) return page.partTitle(parts[0]);
        return "Mise à jour (" + parts.map(p => p.label).join(", ") + ")";
    }
    function stateWord(state) {
        return ({success: "terminée", failed: "en échec", partial: "incomplète", stopped: "arrêtée",
                 interrupted: "interrompue", running: "en cours"}[state] || state || "");
    }
    // Filtre par type d'action : all, activation, adoption, prebuild,
    // flatpak, rollback, check.
    // Filtres croisés : domaine (Nix, Flatpak) et nature (installations,
    // préparatifs) ; une action est montrée si son domaine et sa nature sont
    // actifs. Tous actifs : tout.
    property string domainFilter: "all"
    property string natureFilter: "all"
    function domainOf(t) {
        if (t.id === "check:flatpak") return "flatpak";
        const k = t.part ? t.part.id : t.id === "flatpak" ? ((fp.parts || [])[0] || {}).id || "flatpak"
                : ((t.entry || {}).parts || [{}])[0].id || "";
        return k === "flatpak" || k === "flatpak_download" ? "flatpak" : "nix";
    }
    function kindOf(t) {
        if (t.id.startsWith("check")) return "check";
        if (t.id === "prebuild") return "prebuild";
        if (t.id === "flatpak" && ((fp.parts || [])[0] || {}).id === "flatpak_download") return "prebuild";
        if (t.id === "flatpak") return "flatpak";
        const ids = t.part ? [t.part.id] : ((t.entry || {}).parts || []).map(p => p.id);
        if (ids.length && ids.every(i => i === "flake")) return "adoption";
        if (ids.length && ids.every(i => i === "flatpak_download")) return "prebuild";
        if (ids.length && ids.every(i => i.startsWith("rollback"))) return "rollback";
        if (ids.length && ids.every(i => i === "flatpak")) return "flatpak";
        return "activation";
    }
    // Actions en cours (non filtrées) : aussi les bandeaux du bas de
    // l'onglet Mises à jour. Les recherches n'y sont pas (pas dans le Journal).
    readonly property var runningTasks: {
        const running = [];
        // Mise à jour en cours : une action par partie (en cours, en
        // attente, ou déjà finie).
        if (run.active)
            for (const p of (run.parts || []))
                running.push({ section: "En cours", id: "run:" + p.id, title: page.partTitle(p), part: p,
                               state: p.state === "pending" ? "pending" : p.state,
                               stateText: p.state === "pending" ? "en attente" : "",
                               detail: p.state === "running" ? (run.step || "") : "" });
        // Flatpaks lancés à part.
        if (fp.active)
            running.push({ section: "En cours", id: "flatpak", title: page.partTitle((fp.parts || [])[0] || { id: "flatpak" }),
                           state: "running", detail: "" });
        if (backend.prebuildActive)
            running.push({ section: "En cours", id: "prebuild", title: window.actionTitle("prebuild"), state: "running",
                           // « évaluation de la configuration », puis « 89 % · 120 sur
                           // 146 éléments » (constructions et téléchargements).
                           detail: pre.phase === "eval" || !(pre.fraction >= 0) ? "évaluation de la configuration"
                                 : Math.round(pre.fraction * 100) + " % · "
                                   + (((pre.builds || {}).done || 0) + ((pre.downloads || {}).done || 0)) + "/"
                                   + (((pre.builds || {}).expected || 0) + ((pre.downloads || {}).expected || 0)) + " éléments" });
        return running;
    }
    readonly property var tasks: {
        const running = page.runningTasks.slice(), past = [];
        if (!backend.prebuildActive && result.state)
            past.push({ id: "prebuild", title: window.actionTitle("prebuild"), state: result.state,
                        detail: window.shortWhen(result.time), stateText: result.state === "failed" ? "incomplète" : stateWord(result.state),
                        section: window.daySection(result.time),
                        time: result.time });
        // Anciennes exécutions d'un seul tenant (avant le découpage en
        // actions) : une action par partie aussi, avec le journal complet.
        const hist = [];
        for (const h of backend.history) {
            if ((h.parts || []).length > 1 && !h.group)
                for (const p of h.parts)
                    hist.push(Object.assign({}, h, { id: h.id + "-" + p.id, parts: [p], state: p.state }));
            else hist.push(h);
        }
        for (const h of hist)
            past.push({ id: "h:" + h.id, title: page.entryTitle(h), state: h.state,
                        detail: window.shortWhen(h.finished || h.started),
                        section: window.daySection(h.finished || h.started),
                        time: h.finished || h.started, entry: h });
        past.sort((a, b) => b.time - a.time);
        const all = running.concat(past);
        // Filtre « Installations » : seulement ce qui a changé le système
        // installé (switch système ou Home Manager, retour arrière, mise à
        // jour Flatpak réelle) ; pas les adoptions, préparations (Flatpak
        // --no-deploy compris) ni recherches.
        // Deux groupes : ce qui a changé le système installé, et ce qui le
        // prépare (adoptions, préparations, recherches).
        const install = k => k === "activation" || k === "flatpak" || k === "rollback";
        return all.filter(t => (domainFilter === "all" || page.domainOf(t) === domainFilter)
                            && (natureFilter === "all" || (install(page.kindOf(t)) ? "install" : "prep") === natureFilter));
    }
    // Partie de la mise à jour en cours ouverte (id « run:<partie> »).
    readonly property var openPart: current.startsWith("run:") ? (run.parts || []).find(p => p.id === current.slice(4)) || null : null
    readonly property var selectedEntry: (tasks.find(t => t.id === current) || {}).entry || null

    // En-tête du détail : titre et sous-titre.
    // Titre du détail, état et date à droite ; s'ils ne tiennent pas sur
    // la ligne, ils passent dessous.
    component DetailHeader: GridLayout {
        id: dh
        property string title
        property string subtitle
        readonly property bool narrow: titleLabel.implicitWidth + subLabel.implicitWidth + Kirigami.Units.gridUnit > width
        Layout.fillWidth: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2
        columns: narrow ? 1 : 2
        rowSpacing: 0
        Label {
            id: titleLabel
            Layout.fillWidth: dh.narrow
            text: dh.title
            wrapMode: Text.WordWrap
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        }
        Label {
            id: subLabel
            Layout.fillWidth: true
            text: dh.subtitle
            opacity: 0.7
            elide: Text.ElideRight
            // À droite, même passés sous le titre.
            horizontalAlignment: Text.AlignRight
        }
    }

    // Action ouverte (son détail remplace la liste), ou "" : la liste.
    property string opened: ""
    // L'action ouverte a disparu (fin d'une action en cours) : son entrée
    // d'historique si elle existe, sinon retour à la liste.
    readonly property string current: opened.length === 0 ? ""
        : tasks.some(t => t.id === opened) ? opened : ""
    onVisibleChanged: if (!visible) opened = ""
    // Action en cours ouverte qui se termine : son entrée d'historique.
    onTasksChanged: if (opened.length > 0 && !opened.startsWith("h:") && !tasks.some(t => t.id === opened)) {
        // Partie d'une mise à jour : son entrée « <run>-<partie> ».
        const target = opened.startsWith("run:") ? "h:" + run.id + "-" + opened.slice(4)
                     : opened === "flatpak" ? (tasks.find(t => t.id.startsWith("h:")) || {}).id || "" : "";
        opened = tasks.some(t => t.id === target) ? target : "";
    }
    // Ouvre ce qui tourne (bandeau du bas, tray), sinon la liste.
    function openRunning() {
        const t = tasks.find(x => x.state === "running");
        opened = t ? t.id : "";
    }

    // Filtre de la liste.
    RowLayout {
        Layout.fillWidth: true
        // Deux filtres croisés : domaine et nature.
        SegmentedToggle {
            options: [ { text: "Tout", value: "all" }, { text: "Nix", value: "nix" }, { text: "Flatpak", value: "flatpak" } ]
            value: page.domainFilter
            onValueChanged: page.domainFilter = value
        }
        Item { implicitWidth: Kirigami.Units.largeSpacing }
        SegmentedToggle {
            options: [ { text: "Tout", value: "all" }, { text: "Installations", value: "install" }, { text: "Préparatifs", value: "prep" } ]
            value: page.natureFilter
            onValueChanged: page.natureFilter = value
        }
        Item { Layout.fillWidth: true }
    }
    // Liste pleine largeur.
    ListView {
        // Marge gauche dans la vue : le fond de survol des lignes y déborde
        // sans être coupé.
        leftMargin: Kirigami.Units.largeSpacing
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: page.tasks
        ScrollBar.vertical: FlatScrollBar {}
        section.property: "section"
        // Section courante collée en haut pendant le défilement.
        section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
        section.delegate: SectionHeader {}
        // Même ligne que partout ailleurs (fond léger au survol, même
        // hauteur) ; un clic ouvre le détail. Nom, état en étiquette, heure.
        delegate: ClickableRow {
            id: jrow
            required property var modelData
            // Place pour le débord du fond de survol, et pour la barre de
            // défilement à droite.
            width: ListView.view.width - Kirigami.Units.gridUnit - 2 * Kirigami.Units.largeSpacing
            onClicked: page.opened = jrow.modelData.id
            Label { text: jrow.modelData.title }
            Tag {
                text: jrow.modelData.stateText || page.stateWord(jrow.modelData.state)
                tinted: true
                tint: window.stateColor(jrow.modelData.state)
            }
            Item { Layout.fillWidth: true }
            // Heure, ou étape / avancement pour une action en cours.
            Label {
                text: jrow.modelData.state === "running" && jrow.modelData.detail === "en cours" ? "" : jrow.modelData.detail
                opacity: 0.7
            }
        }
    }

    // Détail de l'action ouverte : une grande fenêtre par-dessus la liste,
    // fermée par « Fermer » ou Échap (la liste reste où elle était).
    Dialog {
        id: detailDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        visible: page.current.length > 0
        onClosed: page.opened = ""
        width: window.largeDialogWidth
        height: window.largeDialogHeight
        padding: Kirigami.Units.largeSpacing * 1.5
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            FlatButton {
                text: "Fermer"
                Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
                onClicked: detailDialog.close()
            }
        }
        contentItem: StackLayout {
            currentIndex: page.current === "prebuild" ? 1 : page.current.startsWith("check") ? 2 : page.current === "flatpak" ? 3
                        : page.current.startsWith("run:") ? 0
                        : page.current.startsWith("h:") ? 4 : 0

            // Mise à jour : parties, étape, avancement, journal.
            ColumnLayout {
                id: runDetail
                spacing: Kirigami.Units.largeSpacing
                readonly property var build: backend.build
                readonly property real buildFraction: {
                    const b = build.builds || {}, d = build.downloads || {};
                    const expected = (b.expected || 0) + (d.expected || 0);
                    return expected > 0 ? Math.min(1, ((b.done || 0) + (b.failed || 0) + (d.done || 0)) / expected) : -1;
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    id: runCard
                    DetailHeader {
                        title: page.openPart ? page.partTitle(page.openPart) : "Mise à jour"
                        subtitle: page.openPart ? (page.openPart.state === "pending" ? "en attente"
                                  : page.stateWord(page.openPart.state)
                                    + (page.openPart.started ? ", lancée " + window.when(page.openPart.started) : "")) : ""
                    }
                    readonly property bool partRunning: !!page.openPart && page.openPart.state === "running"
                    Label {
                        visible: runCard.partRunning && !!page.run.step
                        text: page.run.step || ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    ProgressBar {
                        visible: runCard.partRunning && runDetail.build.phase !== undefined
                        Layout.fillWidth: true
                        from: 0; to: 1
                        indeterminate: runDetail.buildFraction < 0
                        value: Math.max(0, runDetail.buildFraction)
                    }
                    Label {
                        visible: runCard.partRunning && !!page.run.progress
                        text: page.run.progress ? page.run.progress.label + " : " + backend.formatBytes(page.run.progress.bytes) + " téléchargés" : ""
                    }
                }
                // Journal de la partie, relu chaque seconde.
                property string log: ""
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: runDetail.log.length > 0 ? runDetail.log
                        : page.openPart && page.openPart.state === "pending" ? "Cette action commencera quand les précédentes seront finies."
                        : "Le journal s'affichera ici."
                }
                Timer {
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    running: window.visible && page.visible && !!page.openPart && !!page.openPart.log
                    onTriggered: runDetail.log = backend.readLog(page.openPart.log)
                        .split("\n").map(l => l.split("\r").pop()).join("\n")
                }
            }

            // Préparation : avancement de Nix et Flatpak, journal du service.
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    DetailHeader {
                        title: window.actionTitle("prebuild")
                        subtitle: backend.prebuildActive ? (page.pre.boosted ? "à pleine vitesse" : "priorité minimale")
                                : page.result.time ? window.when(page.result.time) : ""
                    }
                    ProgressBar {
                        visible: backend.prebuildActive
                        Layout.fillWidth: true
                        from: 0; to: 1
                        indeterminate: !(page.pre.fraction >= 0)
                        value: page.pre.fraction >= 0 ? page.pre.fraction : 0
                    }
                    Label {
                        visible: backend.prebuildActive && page.pre.phase !== "eval"
                        text: "Constructions : " + (page.pre.builds ? page.pre.builds.done + "/" + page.pre.builds.expected : "–")
                              + "    Téléchargements : " + (page.pre.downloads ? page.pre.downloads.done + "/" + page.pre.downloads.expected : "–")
                    }
                    Label {
                        visible: backend.prebuildActive && (page.pre.building || []).length > 0
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.8
                        text: "Construction : " + (page.pre.building || []).map(b => b.name).slice(0, 3).join(", ")
                    }
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: backend.prebuildLog.length > 0 ? backend.prebuildLog : "Le journal de la préparation s'affichera ici."
                }
                // Journal relu toutes les 2 s tant qu'il est affiché.
                Timer {
                    interval: 2000
                    repeat: true
                    triggeredOnStart: true
                    running: window.visible && page.visible && page.current === "prebuild"
                    onTriggered: backend.refreshPrebuildLog()
                }
            }

            // Recherche des mises à jour : ses étapes en direct (sortie du
            // moteur) ; le résultat s'affiche dans l'onglet Mises à jour.
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                DetailHeader {
                    title: (page.tasks.find(t => t.id === page.current) || {}).title || "Recherche des mises à jour"
                    subtitle: "en cours"
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: backend.checkLog
                }
            }

            // Flatpaks en parallèle : leur journal, relu chaque seconde (il
            // rejoint celui de la mise à jour une fois terminés).
            ColumnLayout {
                id: flatpakDetail
                spacing: Kirigami.Units.largeSpacing
                property string log: ""
                DetailHeader {
                    title: "Mise à jour Flatpak"
                    subtitle: page.fp.active ? "en cours" : page.fp.started ? "lancée " + window.when(page.fp.started) : ""
                }
                MonoText {
                    Layout.fillHeight: true
                    follow: true
                    text: flatpakDetail.log.length > 0 ? flatpakDetail.log : "Le journal des Flatpaks s'affichera ici."
                }
                Timer {
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    running: window.visible && page.visible && page.current === "flatpak" && page.fpLog.length > 0
                    // Barres de progression (\r) : seul leur dernier état.
                    onTriggered: flatpakDetail.log = backend.readLog(page.fpLog)
                        .split("\n").map(l => l.split("\r").pop()).join("\n")
                }
            }

            // Exécution passée : parties, notes, générations activées et
            // journal complet.
            ColumnLayout {
                id: histDetail
                // Largeur imposée par le volet (pas par les longues lignes
                // du journal).
                implicitWidth: 0
                spacing: Kirigami.Units.largeSpacing
                readonly property var h: page.selectedEntry || {}
                // Générations créées pendant l'exécution (rapprochement par
                // les dates), avec la précédente pour revenir en arrière.
                function activated(list) {
                    const t0 = (h.started || 0) - 5, t1 = (h.finished || h.started || 0) + 5;
                    const sorted = (list || []).slice().sort((a, b) => a.number - b.number);
                    const i = sorted.findIndex(g => g.time >= t0 && g.time <= t1);
                    return i < 0 ? null : { gen: sorted[i], prev: i > 0 ? sorted[i - 1] : null };
                }
                // Seulement pour les parties concernées par cette action.
                readonly property var ids: (h.parts || []).map(p => p.id)
                readonly property var sysGen: ids.some(i => i === "system" || i === "rollback_system") ? activated((backend.generations || {}).system) : null
                readonly property var homeGen: ids.some(i => i === "home" || i === "rollback_home") ? activated((backend.generations || {}).home) : null
                property string log: ""
                onHChanged: log = h.log ? backend.readLog(h.log).split("\n").map(l => l.split("\r").pop()).join("\n") : ""
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    DetailHeader {
                        title: page.entryTitle(histDetail.h)
                        subtitle: histDetail.h.started ? page.stateWord(histDetail.h.state) + ", lancée " + window.when(histDetail.h.started) : ""
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Repeater {
                            model: histDetail.h.parts || []
                            Label {
                                required property var modelData
                                text: window.stateGlyph(modelData.state) + " " + modelData.label
                                color: window.stateColor(modelData.state)
                            }
                        }
                    }
                    Repeater {
                        model: histDetail.h.notes || []
                        Label {
                            required property var modelData
                            text: modelData
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                    Repeater {
                        model: [ { kind: "system", label: "Système", g: histDetail.sysGen },
                                 { kind: "home", label: "Home Manager", g: histDetail.homeGen } ].filter(x => x.g)
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.label + " : génération n° " + modelData.g.gen.number
                                      + (modelData.g.gen.current ? " (actuelle)" : "")
                            }
                            FlatButton {
                                visible: !!modelData.g.prev && modelData.g.gen.current
                                enabled: !window.running
                                text: "Revenir à la précédente (n° " + (modelData.g.prev ? modelData.g.prev.number : "") + ")"
                                onClicked: {
                                    const n = modelData.g.prev.number, kind = modelData.kind;
                                    window.ask("Génération " + (kind === "system" ? "système " : "utilisateur ") + n,
                                        "Réactivation de la configuration " + (kind === "system" ? "système" : "utilisateur") + " précédente (génération " + n + ").",
                                        () => kind === "system" ? backend.rollbackSystem(n) : backend.rollbackHome(n));
                                }
                            }
                        }
                    }
                }
                MonoText {
                    Layout.fillHeight: true
                    text: histDetail.log.length > 0 ? histDetail.log : "Journal introuvable (seuls les 30 derniers sont gardés)."
                }
            }
        }
    }
}
