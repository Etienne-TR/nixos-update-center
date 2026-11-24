import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Réglages de la routine : écrits dans ~/.config/<nom>/settings.json par
// dessus ceux de la configuration NixOS, appliqués sans rebuild.
ScrollView {
    ScrollBar.vertical: FlatScrollBar {}
    ScrollBar.horizontal: FlatScrollBar {}
    id: page
    contentWidth: availableWidth
    clip: true

    readonly property var r: backend.routine
    readonly property var days: [
        { key: "Mon", label: "Lun", name: "lundi" }, { key: "Tue", label: "Mar", name: "mardi" },
        { key: "Wed", label: "Mer", name: "mercredi" }, { key: "Thu", label: "Jeu", name: "jeudi" },
        { key: "Fri", label: "Ven", name: "vendredi" }, { key: "Sat", label: "Sam", name: "samedi" },
        { key: "Sun", label: "Dim", name: "dimanche" }
    ]
    // Jours choisis (clés systemd : Mon, Tue…), un ou plusieurs.
    property var chosenDays: ["Wed"]
    property string errorText: ""

    // « Mon,Thu 03:00:00 », « Wed 03:00:00 », « *-*-* 03:00:00 » ou
    // « daily » → jours et heure ; sinon null (laissés tels quels).
    function parse(cal) {
        if (!cal) return null;
        const all = page.days.map(d => d.key);
        if (cal === "daily") return { days: all, hour: 0, minute: 0 };
        const m = /^(?:((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?:,(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun))*)\s+)?(?:\*-\*-\*\s+)?(\d{1,2}):(\d{2})(?::00)?$/.exec(cal);
        return m ? { days: m[1] ? m[1].split(",") : all, hour: parseInt(m[2]), minute: parseInt(m[3]) } : null;
    }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function calendar() {
        // Dans l'ordre de la semaine ; tous les jours : « *-*-* ».
        const d = page.days.map(x => x.key).filter(k => page.chosenDays.includes(k));
        return (d.length === 7 ? "*-*-* " : d.join(",") + " ") + timeField.text + ":00";
    }
    // Enregistrement immédiat à chaque changement (pas de bouton) ; pas
    // pendant le chargement des réglages.
    property bool loading: false
    function save() {
        if (page.loading) return;
        page.errorText = "";
        if (!timeField.acceptableInput) {
            page.errorText = "Heure invalide : format 03:00.";
            return;
        }
        if (page.chosenDays.length === 0) {
            page.errorText = "Au moins un jour est nécessaire.";
            return;
        }
        const cal = page.calendar();
        if (cal === r.calendar && enabledBox.checked === (r.enabled === true)) return;
        backend.saveRoutine({ enabled: enabledBox.checked, calendar: cal });
    }
    function load() {
        page.loading = true;
        enabledBox.checked = r.enabled === true;
        const p = parse(r.calendar || "");
        if (p) {
            page.chosenDays = p.days;
            timeField.text = pad(p.hour) + ":" + pad(p.minute);
        }
        page.loading = false;
    }
    onRChanged: load()
    Component.onCompleted: load()

    Connections {
        target: backend
        function onError(message) { page.errorText = message; }
    }

    contentHeight: content.implicitHeight
    ColumnLayout {
        id: content
        // Aligné à gauche comme les filtres du Journal et de Versions (la
        // marge de l'onglet est commune, dans Main).
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing * 2

        // Une seule section : pas de carte, les réglages directement.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            // Ce qu'est la routine : titre, puis ses actions.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                // Titre, et à droite la prochaine routine (comme les dates
                // dans l'en-tête des cartes).
                // Si les deux ne tiennent pas sur une ligne, la date passe
                // sous le titre.
                GridLayout {
                    id: titleRow
                    Layout.fillWidth: true
                    readonly property bool narrow: titleLabel.implicitWidth + nextLabel.implicitWidth + Kirigami.Units.gridUnit > width
                    columns: narrow ? 1 : 2
                    rowSpacing: 0
                    Label {
                        id: titleLabel
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Recherche et préparation des mises à jour"
                        font.weight: 650
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                    }
                    Label {
                        id: nextLabel
                        // À droite, même passée sous le titre.
                        Layout.alignment: Qt.AlignRight
                        visible: page.r.enabled === true && text.length > 0
                        opacity: 0.7
                        text: page.r.nextTime > 0 ? "prévue " + window.when(page.r.nextTime) : page.r.next ? "prévue : " + page.r.next : ""
                    }
                }
                // Ses actions, en sous-titre.
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    text: "Mise à jour du flake · Construction Nix · Téléchargement des Flatpaks"
                }
            }
            // Réglages, séparés de la description par de l'espace seulement.
            // Une grille : libellés à gauche, contrôles alignés à droite
            // d'eux.
            GridLayout {
                Layout.topMargin: Kirigami.Units.gridUnit
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                rowSpacing: Kirigami.Units.largeSpacing

                Label { text: "Activée" }
                Switch {
                    id: enabledBox
                    onToggled: page.save()
                }

                Label { text: "Jours"; enabled: enabledBox.checked }
                // Un segment par jour, à cocher : un ou plusieurs.
                MultiToggle {
                    id: daysToggle
                    enabled: enabledBox.checked
                    options: page.days.map(d => ({ text: d.label, value: d.key, tooltip: d.name }))
                    values: page.chosenDays
                    onToggled: (v) => { page.chosenDays = v; page.save(); }
                }

                Label { text: "Heure"; enabled: enabledBox.checked }
                // Heure en un seul champ « 03:00 », centré, même allure que
                // le sélecteur des jours (fond teinté, arrondi).
                TextField {
                    id: timeField
                    enabled: enabledBox.checked
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    Layout.preferredHeight: daysToggle.implicitHeight
                    horizontalAlignment: Text.AlignHCenter
                    inputMask: "99:99"
                    validator: RegularExpressionValidator { regularExpression: /([01][0-9]|2[0-3]):[0-5][0-9]/ }
                    text: "03:00"
                    onEditingFinished: page.save()
                    background: Rectangle {
                        radius: daysToggle.radius
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        border.width: timeField.activeFocus ? 1 : 0
                        border.color: Kirigami.Theme.highlightColor
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Si l'ordinateur est éteint à l'heure prévue, la routine sera lancée lors de son redémarrage."
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
            Item { Layout.fillWidth: true }
            // Seulement quand des réglages faits ici remplacent ceux de la
            // configuration NixOS.
            FlatButton {
                visible: page.r.custom === true
                text: "Revenir à la configuration par défaut"
                icon.name: "edit-undo-symbolic"
                onClicked: { page.errorText = ""; backend.resetRoutine(); }
            }
        }
    }
}
