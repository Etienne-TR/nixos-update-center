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

    // Version du paquet principal de l'entrée si elle change (« 1.2 → 1.3 »),
    // sinon les dates ; plus le nombre de commits quand GitHub le donne.
    function revLabel(input) {
        const loc = Qt.locale("fr_FR");
        const day = s => s ? new Date(s * 1000).toLocaleDateString(loc, "d MMM") : "?";
        const parts = [];
        if (!input.from)
            parts.push("nouvelle entrée");
        else if (input.fromVersion && input.toVersion && input.fromVersion !== input.toVersion)
            parts.push(input.fromVersion + " → " + input.toVersion);
        else {
            if (input.toVersion) parts.push("version " + input.toVersion);
            const d1 = day(input.from.date), d2 = day(input.to.date);
            parts.push(d1 === d2 ? d2 : d1 + " → " + d2);
        }
        if (input.commits) parts.push(input.commits + " commit" + (input.commits > 1 ? "s" : ""));
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
                text: page.pending.time ? "Vérifié " + backend.formatTime(page.pending.time) : "Pas encore vérifié"
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
                ToolTip.text: "Config à appliquer (système, Home Manager), nouvelles versions du flake (sans toucher flake.lock), Flatpaks : rien n'est modifié. Lancée aussi à l'ouverture de la fenêtre."
                enabled: !backend.pendingBusy
                onClicked: backend.refreshPending()
            }
        }

        Card {
            title: "Préparation en arrière-plan"
            subtitle: backend.prebuildActive ? (page.pre.boosted ? "à pleine vitesse" : "priorité minimale") : ""

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
                RowLayout {
                    Button {
                        icon.name: "media-seek-forward"
                        text: "Pleine vitesse"
                        enabled: !page.pre.boosted
                        onClicked: backend.boostPrebuild()
                    }
                    Button {
                        icon.name: "process-stop"
                        text: "Arrêter"
                        onClicked: backend.stopPrebuild()
                    }
                    Button {
                        icon.name: "utilities-terminal"
                        text: "Journal"
                        onClicked: backend.openPrebuildJournal()
                    }
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
                Button {
                    icon.name: "run-build"
                    text: "Préparer maintenant"
                    enabled: !window.running
                    onClicked: backend.startPrebuild()
                }
            }
        }

        // ── Bloc 1 : config à appliquer (bouton « Appliquer ») ──
        Repeater {
            model: [ { key: "system", label: "Modifications du système NixOS" },
                     { key: "home", label: "Modifications de Home Manager" } ]
            Card {
                id: partCard
                required property var modelData
                readonly property var st: page.apply[modelData.key] || {}
                Layout.fillWidth: true
                title: modelData.label

                RowLayout {
                    Label {
                        text: partCard.st.changed === true ? "●" : partCard.st.changed === false ? "✓" : "?"
                        color: partCard.st.changed === true ? Kirigami.Theme.neutralTextColor
                             : partCard.st.changed === false ? Kirigami.Theme.positiveTextColor
                             : Kirigami.Theme.disabledTextColor
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: partCard.st.changed === true
                              ? ((partCard.st.commits || []).length + (partCard.st.dirty || []).length > 0
                                 ? "La config diffère de la génération installée : « Appliquer » la reconstruira."
                                 : "Différente de la génération installée (versions du flake.lock, voir plus bas) : « Appliquer » la reconstruira.")
                              : partCard.st.changed === false ? "À jour : « Appliquer » sautera cette partie."
                              : (page.pending.time ? "Évaluation en échec." : "Pas encore vérifié.")
                        wrapMode: Text.WordWrap
                    }
                }

                // Pourquoi : ce qui a changé depuis la dernière application.
                Label {
                    visible: (partCard.st.commits || []).length > 0
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    text: "Commits depuis la dernière application"
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
                    visible: !!partCard.st.diff
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
                    visible: !!partCard.st.diff
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 9
                    text: partCard.st.diff || ""
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Item { Layout.fillWidth: true }
                    Button {
                        icon.name: "system-software-update"
                        text: "Appliquer les modifications"
                        enabled: !window.running && (partCard.st.changed !== false)
                        onClicked: backend.startUpdate([partCard.modelData.key === "system" ? "--system" : "--home"])
                    }
                }
            }
        }

        // ── Bloc 2 : nouvelles versions (bouton « Mettre à jour le flake ») ──

        Card {
            id: flakeNixCard
            readonly property var fl: page.apply.flake || {}
            visible: (fl.commits || []).length + (fl.dirty || []).length > 0
            title: "Modifications de flake.nix"
            subtitle: "entrées du flake, depuis la dernière application"
            Repeater {
                model: flakeNixCard.fl.commits || []
                Label {
                    required property var modelData
                    text: modelData.hash + "  " + modelData.subject
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
            }
            Label {
                visible: ((page.apply.flake || {}).dirty || []).length > 0
                text: "flake.nix modifié, non committé"
                font.family: Kirigami.Theme.fixedWidthFont.family
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "system-software-update"
                    text: "Appliquer les modifications"
                    enabled: !window.running && (true)
                    onClicked: backend.startUpdate(["--system", "--home"])
                }
            }
        }

        Card {
            id: lockCard
            // Entrées du flake.lock déjà mises à jour, pas encore installées
            // (système ou Home Manager).
            readonly property var lockInputs: {
                const seen = {}, out = [];
                for (const i of ((page.apply.system || {}).inputs || []).concat((page.apply.home || {}).inputs || []))
                    if (!seen[i.name]) { seen[i.name] = true; out.push(i); }
                return out;
            }
            visible: lockInputs.length > 0
            title: "Versions du flake.lock pas encore installées"
            Repeater {
                model: lockCard.lockInputs
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.name; font.bold: true }
                    Label {
                        Layout.fillWidth: true
                        text: page.revLabel(modelData)
                    }
                    Kirigami.UrlButton {
                        visible: url.length > 0
                        url: page.compareUrl(modelData)
                        text: "Changements"
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "system-software-update"
                    text: "Appliquer les modifications"
                    enabled: !window.running && (true)
                    onClicked: backend.startUpdate(["--system", "--home"])
                }
            }
        }

        Card {
            title: "Versions des paquets (flake)"
            subtitle: (page.upstream.inputs || []).length > 0 ? page.upstream.inputs.length + " entrée(s) avec une version plus récente" : ""
            RunProgress { partId: "flake" }
            Label {
                visible: (page.upstream.inputs || []).length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: page.upstream.checked ? "Aucune nouvelle version : le flake.lock est à jour."
                                            : "Pas encore vérifié (ou réseau indisponible)."
            }
            Repeater {
                model: page.upstream.inputs || []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.name; font.bold: true }
                    Label {
                        Layout.fillWidth: true
                        text: page.revLabel(modelData)
                    }
                    Kirigami.UrlButton {
                        visible: url.length > 0
                        url: page.compareUrl(modelData)
                        text: "Changements"
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "download"
                    text: "Mettre à jour le flake"
                    enabled: !window.running && (!backend.prebuildActive)
                    onClicked: backend.checkUpdates()
                }
            }
        }


        Card {
            title: "Flatpaks"
            subtitle: (page.pending.flatpaks || []).length > 0 ? page.pending.flatpaks.length + " mise(s) à jour (installées par « Appliquer »)" : ""
            RunProgress { partId: "flatpak" }
            Label {
                visible: (page.pending.flatpaks || []).length === 0
                text: "Aucune mise à jour Flatpak."
                opacity: 0.7
            }
            Repeater {
                model: page.pending.flatpaks || []
                Label {
                    required property var modelData
                    text: modelData.name + "  (" + modelData.id + ", " + modelData.branch + ")"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "system-software-update"
                    text: "Mettre à jour"
                    enabled: !window.running && ((page.pending.flatpaks || []).length > 0)
                    onClicked: backend.startUpdate(["--flatpak"])
                }
            }
        }

        Card {
            visible: !!page.pending.claudeDesktop
            title: "Claude Desktop"
            Label {
                property var c: page.pending.claudeDesktop || {}
                text: c.available ? "Version " + c.latest + " disponible (configurée : " + c.configured + "), écrite dans la config par « Appliquer » (Home Manager)."
                                  : "À jour (" + c.configured + ")."
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                Item { Layout.fillWidth: true }
                Button {
                    icon.name: "system-software-update"
                    text: "Mettre à jour"
                    enabled: !window.running && (!!(page.pending.claudeDesktop && page.pending.claudeDesktop.available))
                    onClicked: backend.startUpdate(["--home"])
                }
            }
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
