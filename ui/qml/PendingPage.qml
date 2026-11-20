import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Ce qui attend d'être installé, et la préparation en arrière-plan.
ScrollView {
    id: page
    contentWidth: availableWidth
    clip: true

    readonly property var pending: backend.pending
    readonly property var apply: pending.apply || {}
    readonly property var upstream: pending.upstream || {}
    readonly property var pre: backend.prebuild
    readonly property var result: backend.prebuildResult

    // Toujours « actuelle → disponible » : version du paquet principal de
    // l'entrée quand elle en a une, et date du commit (avec l'heure si c'est
    // le même jour) ; plus le nombre de commits quand GitHub le donne.
    function revLabel(input) {
        // Retard de la révision que tu as sur la plus récente, en jours
        // (dates des deux commits).
        const lag = (a, b) => {
            if (!a || !b) return "";
            const d = Math.round((b - a) / 86400);
            return d <= 0 ? "< 1 jour" : d === 1 ? "1 jour" : d + " jours";
        };
        if (!input.from) return "nouvelle entrée" + (input.toVersion ? " · " + input.toVersion : "");
        const parts = [];
        // Version si elle est connue : « a → b », ou une seule si elle ne
        // change pas (ou si l'autre est inconnue).
        if (input.fromVersion && input.toVersion && input.fromVersion !== input.toVersion)
            parts.push(input.fromVersion + " → " + input.toVersion);
        else if (input.toVersion || input.fromVersion)
            parts.push(input.toVersion || input.fromVersion);
        // « 936 commits (1 jour) » : nombre de commits, puis le retard.
        const l = lag(input.from.date, input.to.date);
        const c = input.commits ? input.commits + " commit" + (input.commits > 1 ? "s" : "") : "";
        if (c || l) parts.push(c && l ? c + " (" + l + ")" : c || "(" + l + ")");
        return parts.join(" · ");
    }
    function shortDate(secs) {
        return secs ? new Date(secs * 1000).toLocaleDateString(Qt.locale("fr_FR"), "d MMM yyyy") : "?";
    }
    // Message de commit affiché : ceux de flake.lock, faits par le centre
    // (« chore(flake): mise à jour de a, b »), en « flake.lock : a, b ».
    function commitText(subject) {
        const m = /^chore\(flake\): mise à jour (?:de |du )(.*)$/.exec(subject || "");
        return m ? "flake.lock : " + m[1].replace(/^flake\.lock$/, "toutes les entrées") : subject;
    }
    // Installation de la configuration actuelle : la plus récente des
    // générations courantes (système, Home Manager), ou 0.
    function lastInstalled() {
        const g = backend.generations, cur = l => ((l || []).find(x => x.current) || {}).time || 0;
        return Math.max(cur(g.system), cur(g.home));
    }
    // Fin de la dernière exécution où cette partie a réussi (historique), ou 0.
    function lastSuccess(id) {
        let t = 0;
        for (const h of backend.history)
            if ((h.parts || []).some(p => p.id === id && p.state === "success")) t = Math.max(t, h.finished || 0);
        return t;
    }
    function compareUrl(input) {
        if (input.to.type !== "github" || !input.from || !input.from.rev || !input.to.rev) return "";
        return "https://github.com/" + input.to.owner + "/" + input.to.repo + "/compare/"
            + input.from.rev + "..." + input.to.rev;
    }

    // Titre de liste et ligne d'élément de la carte Configuration.
    // Titre de niveau 2 : demi-gras (moins fort que le gras), avec de
    // l'espace au-dessus.
    component Heading: Label {
        Layout.topMargin: Kirigami.Units.largeSpacing
        font.weight: 650  // entre demi-gras (600) et gras (700)
    }
    component ListLine: RowLayout {
        property string text
        property string scope
        property bool mono: true
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            text: parent.text
            elide: Text.ElideRight
            font.family: parent.mono ? Kirigami.Theme.fixedWidthFont.family : Kirigami.Theme.defaultFont.family
        }
        Label { visible: parent.scope.length > 0; text: parent.scope; opacity: 0.6 }
    }

    ColumnLayout {
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing

        Card {
            id: prepCard
            title: "Préparation en arrière-plan"
            // État de la préparation face à ce qui est à appliquer :
            // none (rien à appliquer), ready (tout ce qui est à appliquer est
            // déjà construit), stale (à construire), unknown (évaluation
            // impossible).
            readonly property var sysSt: page.apply.system || {}
            readonly property var homeSt: page.apply.home || {}
            readonly property string prep: {
                const parts = [sysSt, homeSt];
                if (parts.some(p => p.changed !== true && p.changed !== false)) return "unknown";
                const todo = parts.filter(p => p.changed === true);
                if (todo.length === 0) return "none";
                return todo.every(p => p.built) ? "ready" : "stale";
            }
            // En cours : seulement les actions ; l'avancement est dans le
            // bandeau du bas.
            bodyVisible: !backend.prebuildActive
            subtitle: page.result.time ? "préparée " + window.when(page.result.time) : ""
            actions: [
            // En cours : icônes discrètes (l'avancement est dans le bandeau).
            IconAction {
                visible: backend.prebuildActive && !page.pre.boosted
                iconName: "media-seek-forward"
                tooltip: "Passer à pleine vitesse (la préparation tourne en priorité minimale). nixos-update-center-engine boost"
                onClicked: backend.boostPrebuild()
            },
            IconAction {
                visible: backend.prebuildActive
                iconName: "utilities-terminal-symbolic"
                tooltip: "Journal de la préparation (journalctl -f -u nixos-update-center-prebuild, dans un terminal)"
                onClicked: backend.openPrebuildJournal()
            },
            IconAction {
                visible: backend.prebuildActive
                iconName: "process-stop-symbolic"
                tooltip: "Arrêter la préparation (ce qui est déjà construit est gardé). nixos-update-center-engine stop-prebuild"
                onClicked: backend.stopPrebuild()
            },
            Button {
                visible: !backend.prebuildActive && !window.running && (prepCard.prep === "stale" || prepCard.prep === "unknown")
                icon.name: "media-playback-start-symbolic"
                text: "Préparer"
                enabled: !window.running
                onClicked: backend.startPrebuild()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "nixos-update-center-engine start-prebuild : systemctl start nixos-update-center-prebuild, qui construit système et Home Manager sans les activer (nix build en priorité minimale) et télécharge les Flatpaks (flatpak update --no-deploy)."
            }
            ]

            // À l'arrêt.
            RowLayout {
                visible: !backend.prebuildActive
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        const r = page.result;
                        if (prepCard.prep === "none") return "Rien à préparer.";
                        if (prepCard.prep === "ready") return "Prête : Appliquer n'aura qu'à activer.";
                        if (prepCard.prep === "stale") {
                            if (!r.state) return "Pas encore préparée : Appliquer construira tout.";
                            if (r.state === "failed") return "Incomplète : Appliquer construira ce qui manque.";
                            if (r.state === "stopped") return "Arrêtée avant la fin : Appliquer construira ce qui manque.";
                            return "Dépassée : la config a changé depuis la dernière préparation.";
                        }
                        return "État inconnu : la configuration n'a pas pu être évaluée.";
                    }
                }
            }
        }

        // ── Configuration : le dépôt face à ce qui est installé ──
        // Commits, fichiers non committés, entrées adoptées dans flake.lock :
        // tout s'installe par le même rebuild, système et/ou Home Manager,
        // chacun avec sa ligne et son bouton en bas de la carte.
        Card {
            id: confCard
            readonly property var sys: page.apply.system || {}
            readonly property var home: page.apply.home || {}
            readonly property var fl: page.apply.flake || {}
            readonly property bool anyChanged: sys.changed === true || home.changed === true
            readonly property bool allInstalled: sys.changed === false && home.changed === false
            // Portée d'un élément : présent dans la liste de quelles parties.
            function scope(inSys, inHome) {
                return inSys && inHome ? "système et utilisateur" : inSys ? "système" : inHome ? "utilisateur" : "";
            }
            readonly property var unpushed: page.pending.unpushed || []
            // État du dépôt git : fichiers modifiés (pas committés), avec
            // « nouveau » ou « supprimé » selon git, et commits non publiés.
            readonly property var files: (page.pending.uncommitted || []).map(f => {
                const st = f.slice(0, 2);
                return { text: f.slice(3), scope: st === "??" || st.includes("A") ? "nouveau" : st.includes("D") ? "supprimé" : "" };
            })
            readonly property var lockInputs: {
                const seen = {}, out = [];
                for (const i of (sys.inputs || []).concat(home.inputs || []))
                    if (!seen[i.name]) { seen[i.name] = true; out.push(i); }
                return out;
            }
            readonly property var packages: (sys.changed === true ? (sys.packages || []).map(p => Object.assign({ scope: "système" }, p)) : [])
                .concat(home.changed === true ? (home.packages || []).map(p => Object.assign({ scope: "utilisateur" }, p)) : [])

            title: "Configuration Nix"
            subtitle: page.lastInstalled() ? "installée " + window.when(page.lastInstalled()) : ""
            // Rien à montrer (tout installé, dépôt propre) : titre seul.
            bodyVisible: files.length + unpushed.length + lockInputs.length + packages.length > 0
                || sys.changed === null || home.changed === null || allInstalled
            // À appliquer aussi quand seul flake.lock est à enregistrer
            // (entrées adoptées sans effet sur ce qui est installé).
            readonly property bool needsApply: anyChanged || lockInputs.length > 0
            badge: needsApply ? "●" : allInstalled ? "✓" : "?"
            badgeColor: needsApply ? Kirigami.Theme.neutralTextColor
                      : allInstalled ? Kirigami.Theme.positiveTextColor
                      : Kirigami.Theme.negativeTextColor

            Label {
                visible: confCard.allInstalled && confCard.lockInputs.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Rien à appliquer."
            }
            // Évaluation en échec : la dernière erreur de Nix, une fois même
            // si système et Home Manager donnent la même.
            ColumnLayout {
                readonly property var errors: (page.pending.errors || []).map(e => e.trim().replace(/^error: /, ""))
                                                .filter((e, i, a) => e.length > 0 && a.indexOf(e) === i)
                visible: (confCard.sys.changed === null || confCard.home.changed === null) && errors.length > 0
                Layout.fillWidth: true
                spacing: 0
                Label {
                    text: "Évaluation impossible"
                    font.bold: true
                    color: Kirigami.Theme.negativeTextColor
                }
                Repeater {
                    model: parent.errors
                    Label {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        opacity: 0.8
                    }
                }
            }

            Heading {
                visible: confCard.files.length > 0
                Layout.topMargin: (confCard.allInstalled && confCard.lockInputs.length === 0) ? Kirigami.Units.largeSpacing : 0
                text: confCard.files.length > 1 ? "Fichiers modifiés" : "Fichier modifié"
            }
            Repeater {
                model: confCard.files
                ListLine { required property var modelData; text: modelData.text; mono: false; scope: modelData.scope }
            }
            Heading {
                visible: confCard.unpushed.length > 0
                // Pas d'espace au-dessus du premier titre de la carte.
                Layout.topMargin: confCard.files.length > 0 || (confCard.allInstalled && confCard.lockInputs.length === 0) ? Kirigami.Units.largeSpacing : 0
                text: confCard.unpushed.length > 1 ? "Commits non publiés" : "Commit non publié"
            }
            Repeater {
                model: confCard.unpushed
                ListLine { required property var modelData; text: page.commitText(modelData.subject); mono: false }
            }

            // À installer.
            Heading {
                visible: confCard.lockInputs.length > 0
                Layout.topMargin: confCard.files.length + confCard.unpushed.length > 0 || (confCard.allInstalled && confCard.lockInputs.length === 0) ? Kirigami.Units.largeSpacing : 0
                text: confCard.lockInputs.length > 1 ? "Entrées du flake adoptées" : "Entrée du flake adoptée"
            }
            Repeater {
                model: confCard.lockInputs
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData)
                    url: page.compareUrl(modelData)
                }
            }
            Heading {
                // Entrées adoptées sans effet sur ce qui est installé : la
                // partie dit qu'aucun paquet ne change.
                readonly property bool noEffect: confCard.allInstalled && confCard.lockInputs.length > 0
                visible: confCard.packages.length > 0 || noEffect
                text: confCard.packages.length === 1 ? "Paquet prêt à installer" : "Paquets prêts à installer"
            }
            Label {
                visible: confCard.allInstalled && confCard.lockInputs.length > 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Aucun : les entrées adoptées ne changent rien à ce qui est installé. Appliquer enregistre seulement flake.lock (commit et push)."
            }
            Repeater {
                model: confCard.packages.slice(0, 8)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.name }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.8
                        text: modelData.kind.startsWith("A") ? "ajouté" + (modelData.change !== "<none>" ? " (" + modelData.change + ")" : "")
                            : modelData.kind.startsWith("R") ? "retiré"
                            : modelData.change + (modelData.kind.startsWith("D") ? " (version plus ancienne)" : "")
                    }
                    Label { text: modelData.scope; opacity: 0.6 }
                }
            }
            Label {
                visible: confCard.packages.length > 8
                opacity: 0.7
                text: "… et " + (confCard.packages.length - 8) + (confCard.packages.length - 8 > 1 ? " autres" : " autre")
            }

            actions: [
                // « Appliquer » : les deux parties (une partie à jour est
                // sautée). Bouton divisé : la flèche collée à droite, quand les
                // deux sont à appliquer, propose une seule partie.
                RowLayout {
                    visible: (!confCard.allInstalled || confCard.lockInputs.length > 0) && !window.running
                    spacing: 0
                    Button {
                        icon.name: "media-playback-start-symbolic"
                        text: "Appliquer"
                        onClicked: backend.startUpdate(["--system", "--home"])
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "update --system --home : système puis Home Manager ; une partie déjà à jour est sautée. Ensuite commit de flake.lock s'il a changé, push des commits, nh clean."
                    }
                    Button {
                        id: partMenuButton
                        visible: confCard.sys.changed !== false && confCard.home.changed !== false
                        icon.name: "pan-down-symbolic"
                        display: AbstractButton.IconOnly
                        implicitWidth: implicitHeight * 0.8
                        Layout.leftMargin: -1
                        onClicked: partMenu.popup(partMenuButton, 0, partMenuButton.height)
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: "Appliquer une seule partie"
                        Menu {
                            id: partMenu
                            MenuItem {
                                text: "Système seulement"
                                onTriggered: backend.startUpdate(["--system"])
                            }
                            MenuItem {
                                text: "Utilisateur seulement"
                                onTriggered: backend.startUpdate(["--home"])
                            }
                        }
                    }
                },
                IconAction {
                    iconName: "view-refresh-symbolic"
                    enabled: !window.running && !backend.pendingBusy
                    tooltip: "Vérifier la configuration : évaluation du système et de Home Manager (environ 20 s), comparées aux générations installées. nixos-update-center-engine pending --only config"
                    onClicked: backend.refreshPart("config")
                }
            ]
        }

        // ── Mise à jour du flake : nouvelles versions en ligne, à adopter
        // (écrites dans flake.lock) ; elles s'installent ensuite avec la
        // configuration. ──
        Card {
            id: flakeCard
            readonly property var online: page.upstream.inputs || []
            readonly property bool hasOnline: online.length > 0
            title: "Mise à jour du flake"
            subtitle: page.lastSuccess("flake") ? "adoptée " + window.when(page.lastSuccess("flake")) : ""
            bodyVisible: hasOnline || !page.upstream.checked || window.running
            badge: hasOnline ? "●" : (page.upstream.checked ? "✓" : "")
            badgeColor: hasOnline ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor

            RowLayout {
                visible: flakeCard.hasOnline || !page.upstream.checked
                Layout.fillWidth: true
                Heading {
                    Layout.fillWidth: true
                    Layout.topMargin: 0
                    text: page.upstream.checked ? (flakeCard.online.length > 1 ? "Disponibles en ligne" : "Disponible en ligne") : "En ligne : pas encore recherché (ou réseau indisponible)"
                    font.weight: page.upstream.checked ? Font.DemiBold : Font.Normal
                }
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: "Adopter"
                    visible: !window.running && flakeCard.hasOnline
                    enabled: !backend.prebuildActive
                    onClicked: backend.checkUpdates()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Adopter les nouvelles versions : les écrire dans flake.lock (nix flake update), puis, préparer en arrière-plan et notifier (la routine). Rien n'est installé ni committé : flake.lock passe dans « Configuration Nix », committé et publié après une application réussie."
                }
            }
            Repeater {
                model: flakeCard.online
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData)
                    url: page.compareUrl(modelData)
                    updatable: true
                }
            }

            actions: [
                IconAction {
                    iconName: "view-refresh-symbolic"
                    enabled: !window.running && !backend.pendingBusy
                    tooltip: "Rechercher les nouvelles versions en ligne (nix flake update à blanc, sans toucher flake.lock), quelques secondes. Les changements de flake.nix et flake.lock sont vus automatiquement."
                    onClicked: backend.refreshPart("flake")
                }
            ]
        }

        Card {
            id: fpCard
            // Flatpaks en cours de mise à jour : seuls (flatpak-update) ou
            // dans une exécution complète.
            readonly property bool busy: backend.flatpakRun.active === true
                || (window.running && (backend.run.parts || []).some(p => p.id === "flatpak" && (p.state === "running" || p.state === "pending")))
            title: "Flatpaks"
            subtitle: page.lastSuccess("flatpak") ? "mis à jour " + window.when(page.lastSuccess("flatpak")) : ""
            bodyVisible: (page.pending.flatpaks || []).length > 0
            badge: (page.pending.flatpaks || []).length > 0 ? "●" : "✓"
            badgeColor: (page.pending.flatpaks || []).length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            Repeater {
                model: page.pending.flatpaks || []
                // « GIMP  3.2.8 → 3.2.9 · 102,5 Mo (4 jours) » ; même version :
                // nouvelle compilation.
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.name }
                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        opacity: 0.8
                        text: {
                            const m = modelData, parts = [];
                            if (m.fromVersion && m.toVersion)
                                parts.push(m.fromVersion === m.toVersion ? m.toVersion + ", nouvelle compilation" : m.fromVersion + " → " + m.toVersion);
                            let lag = "";
                            if (m.fromDate && m.toDate) {
                                const d = Math.round((m.toDate - m.fromDate) / 86400);
                                lag = d <= 0 ? "< 1 jour" : d === 1 ? "1 jour" : d + " jours";
                            }
                            if (m.size) parts.push(m.size + (lag ? " (" + lag + ")" : ""));
                            else if (lag) parts.push("(" + lag + ")");
                            return parts.join(" · ");
                        }
                        HoverHandler { id: fpHover }
                        ToolTip.visible: fpHover.hovered
                        ToolTip.text: modelData.id + ", " + modelData.branch
                    }
                }
            }
            actions: [
                // Possible pendant une exécution Nix (adopter, appliquer) :
                // les Flatpaks ont leur propre unité.
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: "Mettre à jour"
                    visible: ((page.pending.flatpaks || []).length > 0) && !fpCard.busy
                    onClicked: backend.startFlatpakUpdate()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "nixos-update-center-engine flatpak-update (unité nixos-update-center-flatpak) : flatpak update --user, puis flatpak uninstall --user --unused. Possible pendant une mise à jour Nix."
                },
                IconAction {
                    iconName: "view-refresh-symbolic"
                    enabled: !fpCard.busy && !backend.pendingBusy
                    tooltip: "Rechercher les mises à jour Flatpak seulement : flatpak remote-ls --updates --user. nixos-update-center-engine pending --only flatpak"
                    onClicked: backend.refreshPart("flatpak")
                }
            ]
        }

        Card {
            visible: !!page.pending.claudeDesktop
            title: "Claude Desktop"
            Label {
                property var c: page.pending.claudeDesktop || {}
                text: c.available ? "Version " + c.latest + " disponible (configurée : " + c.configured + "), écrite dans la config par « Appliquer » (Home Manager)."
                                  : "À jour (" + c.configured + ")."
            }
            actions: [
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: "Mettre à jour"
                    enabled: !window.running && (!!(page.pending.claudeDesktop && page.pending.claudeDesktop.available))
                    visible: (!!(page.pending.claudeDesktop && page.pending.claudeDesktop.available)) && !window.running
                    onClicked: backend.startUpdate(["--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --home : écrit la nouvelle version de Claude Desktop dans la config (commit), puis home-manager switch, qui la télécharge et l'installe."
                }
            ]
        }

    }
}
