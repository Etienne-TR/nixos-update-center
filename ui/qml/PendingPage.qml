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
                text: page.pending.time ? "Dernière recherche " + backend.formatTime(page.pending.time) : "Pas encore de recherche"
                // Détail au survol : la config (git) est revérifiée plus souvent.
                HoverHandler { id: timeHover }
                ToolTip.visible: timeHover.hovered && !!page.pending.quickTime
                ToolTip.text: "Recherche complète " + backend.formatTime(page.pending.time)
                              + "\nConfig (git) vérifiée " + backend.formatTime(page.pending.quickTime)
            }
            BusyIndicator {
                visible: backend.pendingBusy
                running: visible
                implicitHeight: Kirigami.Units.iconSizes.medium
                implicitWidth: implicitHeight
            }
            Button {
                icon.name: "view-refresh"
                text: "Rechercher les mises à jour disponibles"
                ToolTip.visible: hovered
                ToolTip.text: "Recherche complète (30 à 60 s) : évaluation du système et de Home Manager, nouvelles versions du flake (sans toucher flake.lock), Flatpaks, Claude Desktop. Rien n'est modifié. La config (git) est aussi vérifiée à l'ouverture et toutes les 5 minutes."
                enabled: !backend.pendingBusy
                onClicked: backend.refreshPending()
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
                visible: !backend.prebuildActive
                icon.name: "run-build"
                text: "Préparer maintenant"
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
                        const when = backend.formatTime(r.time);
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
                readonly property bool showDiff: st.changed === true && !!st.diff
                    && !/No version or selection state changes/.test(st.diff)
                badgeColor: st.changed === true ? Kirigami.Theme.neutralTextColor
                          : st.changed === false ? Kirigami.Theme.positiveTextColor
                          : Kirigami.Theme.negativeTextColor


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
                    visible: partCard.showDiff
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Paquets qui changent (construits par la préparation)"
                    font.bold: true
                }
                Label {
                    visible: partCard.st.changed === null && (page.pending.errors || []).length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.negativeTextColor
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    text: (page.pending.errors || []).join("\n")
                }
                RunProgress { partId: partCard.modelData.key }
                MonoText {
                    visible: partCard.showDiff
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9
                    text: partCard.st.diff || ""
                }
                actions: [
                    Button {
                        icon.name: "system-software-update"
                        text: "Appliquer les modifications"
                        enabled: !window.running && (partCard.st.changed !== false)
                        visible: partCard.st.changed !== false
                        onClicked: backend.startUpdate([partCard.modelData.key === "system" ? "--system" : "--home"])
                        ToolTip.visible: hovered
                        ToolTip.delay: 500
                        ToolTip.text: (partCard.modelData.key === "system" ? "update --system : évaluation, construction de niri patché, nix build du système, sudo nixos-update-center-root switch-to (switch-to-configuration switch), push des commits, nh clean. Sautée si la génération évaluée est déjà installée." : "update --home : Claude Desktop, modèle Voxtype, évaluation, nix build de Home Manager, home-manager switch, push des commits, nh clean. Sautée si la génération évaluée est déjà installée.")
                    }
                ]
            }
        }

        // ── Bloc 2 : nouvelles versions (bouton « Mettre à jour le flake ») ──

        // flake.nix et versions du flake.lock pas encore installées : on ne
        // sait pas laquelle des deux parties ils touchent (l'état de chacune,
        // au-dessus, le dit).
        Card {
            id: flakeCard
            readonly property var fl: page.apply.flake || {}
            readonly property var lockInputs: {
                const seen = {}, out = [];
                for (const i of ((page.apply.system || {}).inputs || []).concat((page.apply.home || {}).inputs || []))
                    if (!seen[i.name]) { seen[i.name] = true; out.push(i); }
                return out;
            }
            visible: (fl.commits || []).length + (fl.dirty || []).length + lockInputs.length > 0
            title: "Entrées du flake"
            badge: "●"
            badgeColor: Kirigami.Theme.neutralTextColor
            Label {
                visible: (flakeCard.fl.commits || []).length > 0
                text: "Commits non appliqués (flake.nix)"
                font.bold: true
            }
            Repeater {
                model: flakeCard.fl.commits || []
                Label {
                    required property var modelData
                    text: modelData.hash + "  " + modelData.subject
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
            }
            Label {
                visible: (flakeCard.fl.dirty || []).length > 0
                text: "flake.nix modifié, non committé"
                font.family: Kirigami.Theme.fixedWidthFont.family
            }
            Label {
                visible: flakeCard.lockInputs.length > 0
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: "Entrées non installées (flake.lock)"
                font.bold: true
            }
            Repeater {
                model: flakeCard.lockInputs
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData)
                    url: page.compareUrl(modelData)
                }
            }
            actions: [
                Button {
                    icon.name: "system-software-update"
                    text: "Appliquer les modifications"
                    enabled: !window.running
                    onClicked: backend.startUpdate(["--system", "--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --system --home : système puis Home Manager, chacun sauté si sa génération évaluée est déjà installée ; push des commits, nh clean après un vrai switch."
                }
            ]
        }

        Card {
            title: "Mise à jour du flake"
            bodyVisible: (page.upstream.inputs || []).length > 0 || !page.upstream.checked
            badge: (page.upstream.inputs || []).length > 0 ? "●" : (page.upstream.checked ? "✓" : "")
            badgeColor: (page.upstream.inputs || []).length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            RunProgress { partId: "flake" }
            Label {
                visible: (page.upstream.inputs || []).length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Pas encore vérifié (ou réseau indisponible)."
            }
            Repeater {
                model: page.upstream.inputs || []
                InputRow {
                    required property var modelData
                    input: modelData
                    label: page.revLabel(modelData)
                    url: page.compareUrl(modelData)
                    updatable: true
                }
            }
            actions: [
                Button {
                    icon.name: "download"
                    text: "Mettre à jour le flake"
                    enabled: !window.running && (!backend.prebuildActive)
                    visible: (page.upstream.inputs || []).length > 0 || !page.upstream.checked
                    onClicked: backend.checkUpdates()
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "nixos-update-center-engine weekly --manual (la routine) : update --flake (nix flake update, commit de flake.lock), puis préparation en arrière-plan, puis notification. Rien n'est installé."
                }
            ]
        }


        Card {
            title: "Flatpaks"
            bodyVisible: (page.pending.flatpaks || []).length > 0
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
                Button {
                    icon.name: "system-software-update"
                    text: "Mettre à jour"
                    enabled: !window.running && ((page.pending.flatpaks || []).length > 0)
                    visible: (page.pending.flatpaks || []).length > 0
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
                    icon.name: "system-software-update"
                    text: "Mettre à jour"
                    enabled: !window.running && (!!(page.pending.claudeDesktop && page.pending.claudeDesktop.available))
                    visible: !!(page.pending.claudeDesktop && page.pending.claudeDesktop.available)
                    onClicked: backend.startUpdate(["--home"])
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "update --home : écrit la nouvelle version de Claude Desktop dans la config (commit), puis home-manager switch, qui la télécharge et l'installe."
                }
            ]
        }

        Card {
            visible: (page.pending.unpushed || []).length > 0
            title: "Commits pas encore envoyés"
            subtitle: "envoyés après une application réussie"
            Repeater {
                model: page.pending.unpushed || []
                Label {
                    required property var modelData
                    text: modelData.hash + "  " + modelData.subject
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
            }
        }
    }
}
