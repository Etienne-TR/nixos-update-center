import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Réglages de la routine : écrits dans ~/.config/<nom>/settings.json par
// dessus ceux de la configuration NixOS, appliqués sans rebuild.
ScrollView {
    id: page
    contentWidth: availableWidth
    clip: true

    readonly property var r: backend.routine
    readonly property var days: [
        { key: "", label: "Tous les jours" },
        { key: "Mon", label: "Lundi" }, { key: "Tue", label: "Mardi" },
        { key: "Wed", label: "Mercredi" }, { key: "Thu", label: "Jeudi" },
        { key: "Fri", label: "Vendredi" }, { key: "Sat", label: "Samedi" },
        { key: "Sun", label: "Dimanche" }
    ]
    property string errorText: ""

    // « Wed 03:00:00 », « *-*-* 03:00:00 » ou « daily » → jour et heure ;
    // sinon horaire avancé, gardé tel quel.
    function parse(cal) {
        if (!cal) return null;
        if (cal === "daily") return { day: "", hour: 0, minute: 0 };
        const m = /^(?:(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+)?(?:\*-\*-\*\s+)?(\d{1,2}):(\d{2})(?::00)?$/.exec(cal);
        return m ? { day: m[1] || "", hour: parseInt(m[2]), minute: parseInt(m[3]) } : null;
    }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function calendar() {
        if (advanced.checked) return advancedField.text.trim();
        const d = page.days[dayBox.currentIndex].key;
        return (d ? d + " " : "*-*-* ") + pad(hourBox.value) + ":" + pad(minuteBox.value) + ":00";
    }
    function load() {
        enabledBox.checked = r.enabled === true;
        flakeBox.checked = r.flakeUpdate !== false;
        flatpakBox.checked = r.flatpak === true;
        notifyBox.checked = r.notify !== false;
        const p = parse(r.calendar || "");
        advanced.checked = p === null && !!r.calendar;
        advancedField.text = r.calendar || "";
        if (p) {
            dayBox.currentIndex = Math.max(0, page.days.findIndex(x => x.key === p.day));
            hourBox.value = p.hour;
            minuteBox.value = p.minute;
        }
    }
    onRChanged: load()
    Component.onCompleted: load()

    Connections {
        target: backend
        function onError(message) { page.errorText = message; }
    }

    ColumnLayout {
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing

        Card {
            title: "Routine"
            subtitle: page.r.next ? "prochaine : " + page.r.next : ""

            Switch {
                id: enabledBox
                text: "Routine activée"
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "La routine cherche les mises à jour et les prépare en arrière-plan, en priorité minimale. Rien n'est installé sans toi. Le bouton « Chercher les mises à jour » la lance à la demande, même désactivée."
            }

            GridLayout {
                columns: 2
                enabled: enabledBox.checked
                columnSpacing: Kirigami.Units.largeSpacing

                Label { text: "Jour" }
                ComboBox {
                    id: dayBox
                    enabled: !advanced.checked
                    model: page.days.map(d => d.label)
                }

                Label { text: "Heure" }
                RowLayout {
                    enabled: !advanced.checked
                    SpinBox { id: hourBox; from: 0; to: 23 }
                    Label { text: "h" }
                    SpinBox { id: minuteBox; from: 0; to: 59; stepSize: 5 }
                }

                CheckBox {
                    id: advanced
                    Layout.columnSpan: 2
                    text: "Horaire avancé (format OnCalendar de systemd)"
                }
                Label { visible: advanced.checked; text: "Horaire" }
                TextField {
                    id: advancedField
                    visible: advanced.checked
                    Layout.fillWidth: true
                    placeholderText: "Mon,Thu 12:30"
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Si l'ordinateur est éteint à l'heure prévue, la routine se lance au démarrage suivant (avec jusqu'à une heure de décalage aléatoire)."
            }
        }

        Card {
            title: "Ce que fait la routine"
            enabled: enabledBox.checked
            CheckBox {
                id: flakeBox
                text: "Mettre à jour le flake (nix flake update, avec commit de flake.lock)"
            }
            CheckBox {
                id: flatpakBox
                text: "Télécharger les mises à jour Flatpak pendant la préparation"
            }
            CheckBox {
                id: notifyBox
                text: "Notifier quand des mises à jour sont disponibles"
            }
        }

        Label {
            visible: page.errorText.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.negativeTextColor
            text: page.errorText
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: page.r.custom ? "Réglages modifiés ici (ils priment sur la configuration NixOS)."
                                    : "Réglages de la configuration NixOS."
            }
            Button {
                visible: page.r.custom === true
                text: "Revenir à la configuration"
                icon.name: "edit-undo"
                onClicked: { page.errorText = ""; backend.resetRoutine(); }
            }
            Button {
                highlighted: true
                icon.name: "document-save"
                text: "Enregistrer"
                onClicked: {
                    page.errorText = "";
                    backend.saveRoutine({
                        enabled: enabledBox.checked,
                        calendar: page.calendar(),
                        flakeUpdate: flakeBox.checked,
                        flatpak: flatpakBox.checked,
                        notify: notifyBox.checked
                    });
                }
            }
        }
    }
}
