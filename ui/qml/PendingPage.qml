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
    function compareUrl(input) {
        if (input.to.type !== "github" || !input.from || !input.from.rev || !input.to.rev) return "";
        return "https://github.com/" + input.to.owner + "/" + input.to.repo + "/compare/"
            + input.from.rev + "..." + input.to.rev;
    }

    // Titre de liste et ligne d'élément de la carte Configuration.
    component Heading: Label {
        Layout.topMargin: Kirigami.Units.smallSpacing
        font.bold: true
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

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                opacity: 0.7
                text: page.pending.time ? "Dernière recherche " + window.when(page.pending.time) : "Pas encore de recherche"
                // Détail au survol : la config (git) est revérifiée plus souvent.
                HoverHandler { id: timeHover }
                ToolTip.visible: timeHover.hovered && !!page.pending.quickTime
                ToolTip.text: "Recherche complète " + window.when(page.pending.time)
                              + "\nConfig (git) vérifiée " + window.when(page.pending.quickTime)
            }
            BusyIndicator {
                visible: backend.pendingBusy
                running: visible
                implicitHeight: Kirigami.Units.iconSizes.medium
                implicitWidth: implicitHeight
            }
            // Même flèche que dans les sections, ici pour tout vérifier.
            IconAction {
                iconName: "view-refresh-symbolic"
                enabled: !backend.pendingBusy
                tooltip: "Tout vérifier (30 à 60 s) : évaluation du système et de Home Manager, nouvelles versions des entrées (sans toucher flake.lock), Flatpaks. Rien n'est modifié. La config (git) est aussi vérifiée à l'ouverture et toutes les 5 minutes."
                onClicked: backend.refreshPending()
            }
        }

        // Ce qui se passe en ce moment, en haut de l'onglet : mise à jour,
        // préparation ou recherche, avec l'étape et l'avancement.
        Frame {
            id: activity
            readonly property bool checking: backend.pendingBusy && !backend.pendingQuick
            visible: window.running || backend.prebuildActive || checking
            Layout.fillWidth: true
            background: Rectangle {
                color: Qt.alpha(Kirigami.Theme.highlightColor, 0.15)
                radius: Kirigami.Units.cornerRadius
            }
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Kirigami.Units.largeSpacing
                BusyIndicator {
                    running: activity.visible
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    implicitWidth: implicitHeight
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.bold: true
                        text: window.running || backend.prebuildActive ? backend.summary
                            : ({ system: "Vérification de la configuration système…",
                                 home: "Vérification de la configuration utilisateur…",
                                 config: "Vérification de la configuration…",
                                 flake: "Recherche des mises à jour des entrées du flake…",
                                 flatpak: "Recherche des mises à jour Flatpak…" }[backend.pendingPart]
                               || "Recherche de toutes les mises à jour…")
                    }
                    ProgressBar {
                        visible: window.running || backend.prebuildActive
                        Layout.fillWidth: true
                        from: 0; to: 1
                        indeterminate: backend.progress < 0
                        value: Math.max(0, backend.progress)
                    }
                }
                IconAction {
                    visible: window.running || backend.prebuildActive
                    iconName: "utilities-terminal-symbolic"
                    tooltip: "Voir le détail et le journal (onglet En cours)"
                    onClicked: window.showRunTab()
                }
            }
        }

        Card {
            title: "Préparation en arrière-plan"
            subtitle: backend.prebuildActive ? (page.pre.boosted ? "à pleine vitesse" : "priorité minimale") : ""
            actions: [
            Button {
                visible: backend.prebuildActive
                icon.name: "media-seek-forward"
                text: "Pleine vitesse"
                enabled: !page.pre.boosted
                onClicked: backend.boostPrebuild()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "nixos-update-center-engine boost : la préparation en cours repasse en priorité normale (sudo nixos-update-center-root boost : chrt, renice, ionice, CPUWeight/IOWeight)."
            },
            Button {
                visible: backend.prebuildActive
                icon.name: "process-stop"
                text: "Arrêter"
                onClicked: backend.stopPrebuild()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "nixos-update-center-engine stop-prebuild : systemctl stop nixos-update-center-prebuild, sans reprise au prochain démarrage. Ce qui est déjà construit est gardé."
            },
            Button {
                visible: backend.prebuildActive
                icon.name: "utilities-terminal"
                text: "Journal"
                onClicked: backend.openPrebuildJournal()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "journalctl -f -u nixos-update-center-prebuild, dans un terminal."
            },
            Button {
                visible: (!backend.prebuildActive) && !window.running
                icon.name: "media-playback-start-symbolic"
                text: "Préparer"
                enabled: !window.running
                onClicked: backend.startPrebuild()
                ToolTip.visible: hovered
                ToolTip.delay: 500
                ToolTip.text: "nixos-update-center-engine start-prebuild : systemctl start nixos-update-center-prebuild, qui construit système et Home Manager sans les activer (nix build en priorité minimale) et télécharge les Flatpaks (flatpak update --no-deploy)."
            }
            ]

            // En cours.
            ColumnLayout {
                visible: backend.prebuildActive
                Layout.fillWidth: true
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 1
                    indeterminate: !(page.pre.fraction >= 0)
                    value: page.pre.fraction >= 0 ? page.pre.fraction : 0
                }
                Label {
                    visible: page.pre.phase === "eval"
                    text: "Évaluation de la configuration…"
                }
                Label {
                    visible: page.pre.phase !== "eval"
                    text: "Constructions : " + (page.pre.builds ? page.pre.builds.done + "/" + page.pre.builds.expected : "–")
                          + (page.pre.builds && page.pre.builds.failed > 0 ? ", " + page.pre.builds.failed + " en échec" : "")
                          + "    Téléchargements : " + (page.pre.downloads ? page.pre.downloads.done + "/" + page.pre.downloads.expected : "–")
                }
                Repeater {
                    model: (page.pre.building || []).slice(0, 3)
                    Label {
                        required property var modelData
                        text: "En cours : " + modelData.name + (modelData.phase ? " (" + modelData.phase + ")" : "")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                Label {
                    visible: !!page.pre.flatpak
                    text: page.pre.flatpak === "running" ? "Flatpak : téléchargement en cours"
                          : page.pre.flatpak === "done" ? "Flatpak : mises à jour téléchargées"
                          : "Flatpak : téléchargement en échec"
                }
            }

            // À l'arrêt.
            RowLayout {
                visible: !backend.prebuildActive
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        const r = page.result;
                        if (!r.state) return "Aucune préparation pour l'instant. Elle se lance avec la routine hebdomadaire.";
                        const when = window.when(r.time);
                        if (r.state === "success") return "Dernière préparation terminée " + when + ".";
                        if (r.state === "failed") return "Dernière préparation incomplète " + when + " : la mise à jour reprendra ce qui manque.";
                        return "Dernière préparation arrêtée " + when + ".";
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
            // État du dépôt git, une ligne par élément : fichier non committé
            // (« nouveau », « supprimé » selon git status) ou commit non publié.
            // État du dépôt git, une ligne par élément : fichier modifié (pas
            // committé) ou commit non publié. Ce qui reste à appliquer
            // se lit aux boutons de la carte.
            readonly property var repoLines: (page.pending.uncommitted || []).map(f => {
                const st = f.slice(0, 2), path = f.slice(3);
                return { text: path, scope: st === "??" || st.includes("A") ? "nouveau"
                                          : st.includes("D") ? "supprimé" : "modifié" };
            }).concat(unpushed.map(c => ({ text: page.commitText(c.subject), scope: "non publié" })))
            readonly property var lockInputs: {
                const seen = {}, out = [];
                for (const i of (sys.inputs || []).concat(home.inputs || []))
                    if (!seen[i.name]) { seen[i.name] = true; out.push(i); }
                return out;
            }
            readonly property var packages: (sys.changed === true ? (sys.packages || []).map(p => Object.assign({ scope: "système" }, p)) : [])
                .concat(home.changed === true ? (home.packages || []).map(p => Object.assign({ scope: "utilisateur" }, p)) : [])

            title: "Configuration Nix"
            badge: anyChanged ? "●" : allInstalled ? "✓" : "?"
            badgeColor: anyChanged ? Kirigami.Theme.neutralTextColor
                      : allInstalled ? Kirigami.Theme.positiveTextColor
                      : Kirigami.Theme.negativeTextColor

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
                visible: confCard.repoLines.length > 0
                Layout.topMargin: 0
                text: "État du dépôt git"
                HoverHandler { id: repoHover }
                ToolTip.visible: repoHover.hovered
                ToolTip.text: "Modifié : fichier pas encore committé (le centre ne committe que flake.lock, après une application réussie). Non publié : commit pas encore sur GitHub (git push après une application réussie)."
            }
            Repeater {
                model: confCard.repoLines
                ListLine { required property var modelData; text: modelData.text; scope: modelData.scope }
            }

            // À installer.
            Heading {
                visible: confCard.lockInputs.length > 0
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
                visible: confCard.packages.length > 0
                text: confCard.packages.length > 1 ? "Paquets qui changent" : "Paquet qui change"
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

            // Avancement de la partie en cours pendant une application.
            RunProgress { partId: "system" }
            RunProgress { partId: "home" }

            actions: [
                IconAction {
                    iconName: "view-refresh-symbolic"
                    visible: !window.running
                    enabled: !backend.pendingBusy
                    tooltip: "Vérifier la configuration : évaluation du système et de Home Manager (environ 20 s), comparées aux générations installées. nixos-update-center-engine pending --only config"
                    onClicked: backend.refreshPart("config")
                },
                // Une partie seule, quand les deux sont à appliquer ; sinon
                // « Appliquer » suffit (une partie à jour est sautée).
                Button {
                    text: "Système"
                    visible: confCard.sys.changed !== false && confCard.home.changed !== false && !window.running
                    onClicked: backend.startUpdate(["--system"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --system : évaluation, niri patché, nix build du système, sudo nixos-update-center-root switch-to (switch-to-configuration switch), puis commit de flake.lock s'il a changé, push, nh clean."
                },
                Button {
                    text: "Utilisateur"
                    visible: confCard.sys.changed !== false && confCard.home.changed !== false && !window.running
                    onClicked: backend.startUpdate(["--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --home : Claude Desktop, modèle Voxtype, nix build de Home Manager, home-manager switch, puis commit de flake.lock s'il a changé, push, nh clean."
                },
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: confCard.sys.changed !== false && confCard.home.changed !== false ? "Tout"
                        : confCard.sys.changed !== false ? "Appliquer (système)" : "Appliquer (utilisateur)"
                    visible: !confCard.allInstalled && !window.running
                    onClicked: backend.startUpdate(["--system", "--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --system --home : système puis Home Manager ; une partie déjà à jour est sautée. Ensuite commit de flake.lock s'il a changé, push des commits, nh clean."
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
            bodyVisible: hasOnline || !page.upstream.checked || window.running
            badge: hasOnline ? "●" : (page.upstream.checked ? "✓" : "")
            badgeColor: hasOnline ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            RunProgress { partId: "flake" }

            RowLayout {
                visible: flakeCard.hasOnline || !page.upstream.checked
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: page.upstream.checked ? (flakeCard.online.length > 1 ? "Disponibles en ligne" : "Disponible en ligne") : "En ligne : pas encore recherché (ou réseau indisponible)"
                    font.bold: page.upstream.checked
                    opacity: page.upstream.checked ? 1 : 0.7
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
                    visible: !window.running
                    enabled: !backend.pendingBusy
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
            bodyVisible: (page.pending.flatpaks || []).length > 0 || busy
            badge: (page.pending.flatpaks || []).length > 0 ? "●" : "✓"
            badgeColor: (page.pending.flatpaks || []).length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            RunProgress { partId: "flatpak" }
            RowLayout {
                visible: backend.flatpakRun.active === true
                Layout.fillWidth: true
                BusyIndicator {
                    running: parent.visible
                    implicitHeight: Kirigami.Units.iconSizes.small
                    implicitWidth: implicitHeight
                }
                Label { text: "Mise à jour en cours…"; Layout.fillWidth: true }
                IconAction {
                    iconName: "utilities-terminal-symbolic"
                    tooltip: "Voir le journal (onglet En cours)"
                    onClicked: window.showRunTab()
                }
            }
            Repeater {
                model: page.pending.flatpaks || []
                // « GIMP  3.2.8 → 3.2.9 · 102,5 Mo (4 jours) » ; même version :
                // nouvelle compilation.
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.name; font.bold: true }
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
                IconAction {
                    iconName: "view-refresh-symbolic"
                    visible: !fpCard.busy
                    enabled: !backend.pendingBusy
                    tooltip: "Rechercher les mises à jour Flatpak seulement : flatpak remote-ls --updates --user. nixos-update-center-engine pending --only flatpak"
                    onClicked: backend.refreshPart("flatpak")
                },
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
