import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Exécutions passées, générations (avec retour arrière) et nouveautés de
// Home Manager.
ScrollView {
    id: page
    contentWidth: availableWidth
    clip: true

    component Generations: Card {
        id: gens
        property var model: []
        property string kind
        Label {
            visible: gens.model.length === 0
            text: "Aucune génération trouvée."
            opacity: 0.7
        }
        Repeater {
            model: gens.model.slice().reverse().slice(0, 10)
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Label {
                    text: "n° " + modelData.number
                    font.bold: modelData.current
                }
                Label {
                    Layout.fillWidth: true
                    text: backend.formatTime(modelData.time) + (modelData.version ? "  ·  " + modelData.version : "")
                    elide: Text.ElideRight
                    opacity: 0.8
                }
                Label {
                    visible: modelData.current
                    text: "actuelle"
                    color: Kirigami.Theme.positiveTextColor
                }
                Button {
                    visible: !modelData.current
                    enabled: !window.running
                    text: "Revenir à celle-ci"
                    flat: true
                    onClicked: window.ask("Revenir à la génération " + modelData.number + " ?",
                        gens.kind === "system"
                            ? "Le système est réactivé dans l'état de cette génération (paquets et services). Une prochaine mise à jour reviendra à la configuration actuelle."
                            : "Home Manager est réactivé dans l'état de cette génération. Une prochaine mise à jour reviendra à la configuration actuelle.",
                        () => gens.kind === "system" ? backend.rollbackSystem(modelData.number)
                                                     : backend.rollbackHome(modelData.number))
                }
            }
        }
    }

    ColumnLayout {
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing

        Card {
            title: "Mises à jour passées"
            Label {
                visible: backend.history.length === 0
                text: "Aucune mise à jour enregistrée pour l'instant."
                opacity: 0.7
            }
            Repeater {
                model: backend.history.slice(0, 15)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label {
                        text: window.stateGlyph(modelData.state === "partial" ? "failed" : modelData.state)
                        color: window.stateColor(modelData.state)
                        font.bold: true
                    }
                    Label {
                        text: backend.formatTime(modelData.started)
                    }
                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.8
                        text: (modelData.parts || []).map(p => window.stateGlyph(p.state) + " " + p.label).join("   ")
                              + ((modelData.notes || []).length > 0 ? "   ·   " + modelData.notes.join(", ") : "")
                    }
                    Button {
                        flat: true
                        icon.name: "document-preview"
                        text: "Journal"
                        onClicked: window.showLog(window.runTitle(modelData.state) + ", " + backend.formatTime(modelData.started), modelData.log)
                    }
                }
            }
        }

        Generations {
            title: "Générations du système"
            kind: "system"
            model: backend.generations.system || []
        }

        Generations {
            title: "Générations de Home Manager"
            kind: "home"
            model: backend.generations.home || []
        }

        Card {
            title: "Nouveautés de Home Manager"
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: backend.news.length > 0 ? backend.news : "Aucune."
                textFormat: Text.PlainText
            }
        }
    }
}
