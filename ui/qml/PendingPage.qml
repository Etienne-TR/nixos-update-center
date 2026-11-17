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
    readonly property var pre: backend.prebuild
    readonly property var result: backend.prebuildResult

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
                icon.name: "system-software-update"
                text: "Chercher les mises à jour"
                enabled: !window.running && !backend.prebuildActive
                ToolTip.visible: hovered
                ToolTip.text: "Lance la routine du mercredi : nix flake update (commit de flake.lock, envoyé après une mise à jour réussie), préparation en arrière-plan, notification."
                onClicked: backend.checkUpdates()
            }
            Button {
                icon.name: "view-refresh"
                text: "Vérifier"
                ToolTip.visible: hovered
                ToolTip.text: "Recalcule ce qui attend d'être installé, sans rien modifier."
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

        Card {
            title: "Entrées du flake"
            subtitle: (page.pending.inputs || []).length > 0 ? (page.pending.inputs.length + " changée(s) depuis le dernier switch") : ""
            Label {
                visible: (page.pending.inputs || []).length === 0
                text: "Aucune entrée n'a changé depuis le dernier switch du système."
                opacity: 0.7
            }
            Repeater {
                model: page.pending.inputs || []
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label {
                        text: modelData.name
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: (modelData.from ? page.shortDate(modelData.from.date) : "nouvelle") + " → " + page.shortDate(modelData.to.date)
                    }
                    Kirigami.UrlButton {
                        visible: url.length > 0
                        url: page.compareUrl(modelData)
                        text: "Changements"
                    }
                }
            }
        }

        Card {
            title: "Paquets du système"
            Label {
                visible: !page.pending.system || !page.pending.system.diff
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: page.pending.system && page.pending.system.built
                      ? "La génération préparée est déjà celle du système."
                      : "Pas encore construit : la préparation en arrière-plan affichera ici les paquets qui changent."
            }
            MonoText {
                visible: !!(page.pending.system && page.pending.system.diff)
                Layout.preferredHeight: Kirigami.Units.gridUnit * 12
                text: page.pending.system ? page.pending.system.diff : ""
            }
        }

        Card {
            title: "Paquets de Home Manager"
            Label {
                visible: !page.pending.home || !page.pending.home.diff
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: page.pending.home && page.pending.home.built
                      ? "La génération préparée est déjà celle de Home Manager."
                      : "Pas encore construit : la préparation en arrière-plan affichera ici les paquets qui changent."
            }
            MonoText {
                visible: !!(page.pending.home && page.pending.home.diff)
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                text: page.pending.home ? page.pending.home.diff : ""
            }
        }

        Card {
            title: "Flatpaks"
            subtitle: (page.pending.flatpaks || []).length > 0 ? page.pending.flatpaks.length + " mise(s) à jour" : ""
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
        }

        Card {
            visible: !!page.pending.claudeDesktop
            title: "Claude Desktop"
            Label {
                property var c: page.pending.claudeDesktop || {}
                text: c.available ? "Version " + c.latest + " disponible (configurée : " + c.configured + "), installée avec Home Manager."
                                  : "À jour (" + c.configured + ")."
            }
        }

        Card {
            visible: (page.pending.unpushed || []).length > 0
            title: "Commits pas encore envoyés"
            subtitle: "envoyés après une mise à jour réussie"
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
