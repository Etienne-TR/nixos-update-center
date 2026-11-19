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
        if (input.fromVersion || input.toVersion)
            parts.push((input.fromVersion || "?") + " → " + (input.toVersion || "?"));
        // « 936 commits (1 jour) » : nombre de commits, puis le retard.
        const l = lag(input.from.date, input.to.date);
        const c = input.commits ? input.commits + " commit" + (input.commits > 1 ? "s" : "") : "";
        if (c || l) parts.push(c && l ? c + " (" + l + ")" : c || "(" + l + ")");
        return parts.join(" · ");
    }
    function shortDate(secs) {
        return secs ? new Date(secs * 1000).toLocaleDateString(Qt.locale("fr_FR"), "d MMM yyyy") : "?";
    }
    function compareUrl(input) {
        if (input.to.type !== "github" || !input.from || !input.from.rev || !input.to.rev) return "";
        return "https://github.com/" + input.to.owner + "/" + input.to.repo + "/compare/"
            + input.from.rev + "..." + input.to.rev;
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

        // Commits locaux pas encore sur GitHub : une ligne discrète (envoyés
        // après une application réussie), le détail au survol.
        Label {
            readonly property var list: page.pending.unpushed || []
            visible: list.length > 0
            Layout.fillWidth: true
            opacity: 0.7
            elide: Text.ElideRight
            text: list.length + " commit" + (list.length > 1 ? "s" : "") + " pas encore envoyé" + (list.length > 1 ? "s" : "")
                  + " sur GitHub (envoyé" + (list.length > 1 ? "s" : "") + " après une application réussie)"
            HoverHandler { id: unpushedHover }
            ToolTip.visible: unpushedHover.hovered
            ToolTip.text: list.map(c => c.hash + "  " + c.subject).join("\n")
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

        // ── Bloc 1 : config à appliquer (bouton « Appliquer ») ──
        Repeater {
            model: [ { key: "system", label: "Configuration système (NixOS)" },
                     { key: "home", label: "Configuration utilisateur (Home Manager)" } ]
            Card {
                id: partCard
                required property var modelData
                readonly property var st: page.apply[modelData.key] || {}
                Layout.fillWidth: true
                title: modelData.label
                // État : pastille après le titre (● à appliquer, ✓ à jour).
                badge: st.changed === true ? "●" : st.changed === false ? "✓" : "?"
                // Liste nvd seulement si la partie est à appliquer et qu'une
                // version de paquet change (sinon nvd ne dit que « No version
                // … changes »).
                bodyVisible: st.changed !== false || backend.run.active === true
                readonly property var packages: st.changed === true ? (st.packages || []) : []
                badgeColor: st.changed === true ? Kirigami.Theme.neutralTextColor
                          : st.changed === false ? Kirigami.Theme.positiveTextColor
                          : Kirigami.Theme.negativeTextColor


                // Évaluation en échec : la dernière erreur de Nix.
                Label {
                    visible: partCard.st.changed === null && (page.pending.errors || []).length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.negativeTextColor
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    text: (page.pending.errors || []).join("\n")
                }
                // Partie en cours de mise à jour : étape et avancement.
                RunProgress { partId: partCard.modelData.key }
                // Pourquoi : ce qui a changé depuis la dernière application.
                Label {
                    visible: (partCard.st.commits || []).length > 0
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Commits non appliqués"
                    font.bold: true
                }
                Repeater {
                    model: partCard.st.commits || []
                    Label {
                        required property var modelData
                        text: modelData.hash + "  " + modelData.subject
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        font.family: Kirigami.Theme.fixedWidthFont.family
                    }
                }
                Label {
                    visible: (partCard.st.dirty || []).length > 0
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Fichiers modifiés non committés"
                    font.bold: true
                }
                Repeater {
                    model: partCard.st.dirty || []
                    Label {
                        required property var modelData
                        text: modelData.trim()
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        font.family: Kirigami.Theme.fixedWidthFont.family
                    }
                }
                Label {
                    visible: partCard.packages.length > 0
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Paquets qui changent"
                    font.bold: true
                }
                Repeater {
                    model: partCard.packages.slice(0, 8)
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
                    }
                }
                Label {
                    visible: partCard.packages.length > 8
                    opacity: 0.7
                    text: "… et " + (partCard.packages.length - 8) + " autre(s)"
                }
                actions: [
                    IconAction {
                        iconName: "view-refresh-symbolic"
                        visible: !window.running
                        enabled: !backend.pendingBusy
                        tooltip: "Vérifier cette partie seulement : évaluation (environ 10 s), comparée à la génération installée. nixos-update-center-engine pending --only " + partCard.modelData.key
                        onClicked: backend.refreshPart(partCard.modelData.key)
                    },
                    Button {
                        icon.name: "media-playback-start-symbolic"
                        text: "Appliquer"
                        enabled: !window.running && (partCard.st.changed !== false)
                        visible: (partCard.st.changed !== false) && !window.running
                        onClicked: backend.startUpdate([partCard.modelData.key === "system" ? "--system" : "--home"])
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: (partCard.modelData.key === "system" ? "update --system : évaluation, construction de niri patché, nix build du système, sudo nixos-update-center-root switch-to (switch-to-configuration switch), push des commits, nh clean. Sautée si la génération évaluée est déjà installée." : "update --home : Claude Desktop, modèle Voxtype, évaluation, nix build de Home Manager, home-manager switch, push des commits, nh clean. Sautée si la génération évaluée est déjà installée.")
                    }
                ]
            }
        }

        // ── Bloc 2 : nouvelles versions (bouton « Mettre à jour le flake ») ──

        // Mise à jour du flake : tout le chemin d'une entrée au même endroit.
        // Nouvelle version en ligne → adoptée dans flake.lock → installée
        // (« Appliquer »). flake.nix modifié : une ligne.
        Card {
            id: flakeCard
            readonly property var fl: page.apply.flake || {}
            // Adoptées dans flake.lock, pas encore installées (système ou
            // Home Manager).
            readonly property var lockInputs: {
                const seen = {}, out = [];
                for (const i of ((page.apply.system || {}).inputs || []).concat((page.apply.home || {}).inputs || []))
                    if (!seen[i.name]) { seen[i.name] = true; out.push(i); }
                return out;
            }
            readonly property var online: page.upstream.inputs || []
            readonly property bool hasChanges: (fl.commits || []).length + (fl.dirty || []).length + lockInputs.length > 0
            readonly property bool hasOnline: online.length > 0
            title: "Mise à jour du flake"
            bodyVisible: hasChanges || hasOnline || !page.upstream.checked || window.running
            badge: hasChanges || hasOnline ? "●" : (page.upstream.checked ? "✓" : "")
            badgeColor: hasChanges || hasOnline ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            RunProgress { partId: "flake" }
            // Nouvelles versions en ligne (▶ au survol : adopter cette entrée).
            Repeater {
                model: flakeCard.online
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData) + " · en ligne"
                    url: page.compareUrl(modelData)
                    updatable: true
                }
            }
            // Adoptées, à installer.
            Repeater {
                model: flakeCard.lockInputs
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData) + " · adoptée, à installer"
                    url: page.compareUrl(modelData)
                }
            }
            Label {
                readonly property int n: (flakeCard.fl.commits || []).length
                readonly property bool dirty: (flakeCard.fl.dirty || []).length > 0
                visible: n > 0 || dirty
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "flake.nix modifié" + (n > 0 ? " (" + n + " commit" + (n > 1 ? "s" : "") + ")" : "")
                      + (dirty ? (n > 0 ? ", plus des modifications non committées" : ", non committé") : "")
                HoverHandler { id: flakeNixHover }
                ToolTip.visible: flakeNixHover.hovered && n > 0
                ToolTip.text: (flakeCard.fl.commits || []).map(c => c.hash + "  " + c.subject).join("\n")
            }
            Label {
                visible: !page.upstream.checked && !window.running
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Nouvelles versions en ligne pas encore recherchées (ou réseau indisponible)."
            }
            actions: [
                IconAction {
                    iconName: "view-refresh-symbolic"
                    visible: !window.running
                    enabled: !backend.pendingBusy
                    tooltip: "Rechercher les nouvelles versions en ligne (nix flake update à blanc, sans toucher flake.lock) et ce qui a changé dans flake.nix et flake.lock (quelques secondes). nixos-update-center-engine pending --only flake"
                    onClicked: backend.refreshPart("flake")
                },
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: "Adopter"
                    enabled: !backend.prebuildActive
                    visible: (flakeCard.hasOnline || !page.upstream.checked) && !window.running
                    onClicked: backend.checkUpdates()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Adopter les nouvelles versions : les écrire dans flake.lock (nix flake update, avec commit), puis préparer en arrière-plan et notifier (la routine, nixos-update-center-engine weekly --manual). Rien n'est installé."
                },
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: flakeCard.hasOnline ? "Adopter et appliquer" : "Appliquer"
                    visible: (flakeCard.hasOnline || flakeCard.hasChanges) && !window.running
                    onClicked: backend.startUpdate(flakeCard.hasOnline ? ["--flake", "--system", "--home"] : ["--system", "--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: flakeCard.hasOnline
                        ? "update --flake --system --home : adopter les nouvelles versions (nix flake update, avec commit), puis les installer : système puis Home Manager, chacun sauté s'il est déjà à jour."
                        : "update --system --home : installer ce qui a été adopté : système puis Home Manager, chacun sauté s'il est déjà à jour."
                }
            ]
        }

        Card {
            title: "Flatpaks"
            bodyVisible: (page.pending.flatpaks || []).length > 0 || window.running
            badge: (page.pending.flatpaks || []).length > 0 ? "●" : "✓"
            badgeColor: (page.pending.flatpaks || []).length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            RunProgress { partId: "flatpak" }
            Repeater {
                model: page.pending.flatpaks || []
                Label {
                    required property var modelData
                    text: modelData.name + "  (" + modelData.id + ", " + modelData.branch + ")"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            actions: [
                IconAction {
                    iconName: "view-refresh-symbolic"
                    visible: !window.running
                    enabled: !backend.pendingBusy
                    tooltip: "Rechercher les mises à jour Flatpak seulement : flatpak remote-ls --updates --user. nixos-update-center-engine pending --only flatpak"
                    onClicked: backend.refreshPart("flatpak")
                },
                Button {
                    icon.name: "media-playback-start-symbolic"
                    text: "Mettre à jour"
                    enabled: !window.running && ((page.pending.flatpaks || []).length > 0)
                    visible: ((page.pending.flatpaks || []).length > 0) && !window.running
                    onClicked: backend.startUpdate(["--flatpak"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --flatpak : flatpak update --user, puis flatpak uninstall --user --unused."
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
