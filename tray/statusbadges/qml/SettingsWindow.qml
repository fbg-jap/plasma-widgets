import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Add, configure, reorder and remove widgets, plus app-wide settings.
Window {
    id: win
    title: "Status Badges – Settings"
    width: 860
    height: 640
    minimumWidth: 700
    minimumHeight: 480
    color: sys.window

    SystemPalette { id: sys; colorGroup: SystemPalette.Active }

    property int selected: 0
    readonly property var widget: controller.widgets.length > 0
        ? controller.widgets[Math.min(selected, controller.widgets.length - 1)] : null
    // The edited copy of the selected widget's settings; written back with Save.
    property var draft: ({})
    property int secretTick: 0   // bump to re-check whether keys are stored

    function loadDraft() {
        draft = widget ? JSON.parse(JSON.stringify(widget.settings)) : ({})
        secretTick++
    }
    onWidgetChanged: loadDraft()

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ---- widget list -------------------------------------------------------------
        ColumnLayout {
            Layout.preferredWidth: 250
            Layout.fillHeight: true

            Label { text: "Widgets"; font.bold: true }

            Frame {
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 2

                ListView {
                    id: widgetList
                    anchors.fill: parent
                    clip: true
                    model: controller.widgets
                    currentIndex: win.selected
                    delegate: ItemDelegate {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        highlighted: index === win.selected
                        text: modelData.name
                        onClicked: win.selected = index
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                ComboBox {
                    id: kindBox
                    Layout.fillWidth: true
                    textRole: "name"
                    model: controller.providerKinds()
                }
                Button {
                    text: "Add"
                    onClicked: {
                        controller.addWidget(kindBox.model[kindBox.currentIndex].kind)
                        win.selected = controller.widgets.length - 1
                        win.loadDraft()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                enabled: win.widget !== null
                GlyphButton { glyph: "up"; tip: "Move up"; onClicked: { controller.moveWidget(win.widget.wid, -1); win.selected = Math.max(0, win.selected - 1) } }
                GlyphButton { glyph: "down"; tip: "Move down"; onClicked: { controller.moveWidget(win.widget.wid, 1); win.selected = Math.min(controller.widgets.length - 1, win.selected + 1) } }
                Item { Layout.fillWidth: true }
                Button {
                    text: "Remove"
                    onClicked: {
                        controller.removeWidget(win.widget.wid)
                        win.selected = Math.max(0, win.selected - 1)
                        win.loadDraft()
                    }
                }
            }
        }

        // ---- editor ------------------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ScrollView {
                id: editorScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                visible: win.widget !== null

                GridLayout {
                    width: editorScroll.availableWidth - 12
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8

                    Label { text: "Type:"; Layout.preferredWidth: 140 }
                    Label {
                        Layout.fillWidth: true
                        text: win.widget ? (controller.providerKinds().find(p => p.kind === win.widget.kind) || {}).description || "" : ""
                        wrapMode: Text.Wrap
                        opacity: 0.75
                    }

                    Label { text: "Name:"; Layout.preferredWidth: 140 }
                    TextField {
                        Layout.fillWidth: true
                        text: win.draft.name || ""
                        onTextEdited: win.draft.name = text
                    }

                    // Provider-specific fields (server, account, keys, ...)
                    Repeater {
                        model: win.widget ? controller.fieldsFor(win.widget.kind) : []

                        delegate: Item {
                            required property var modelData
                            // Each field spans both grid columns: label + input in its own row.
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            implicitHeight: fieldRow.implicitHeight

                            RowLayout {
                                id: fieldRow
                                width: parent.width
                                spacing: 12

                                Label {
                                    Layout.preferredWidth: 140
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 6
                                    text: modelData.label + ":"
                                    wrapMode: Text.Wrap
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    TextField {
                                        Layout.fillWidth: true
                                        visible: modelData.type === "text"
                                        placeholderText: modelData.placeholder
                                        text: win.draft[modelData.key] || ""
                                        onTextEdited: win.draft[modelData.key] = text
                                    }

                                    SpinBox {
                                        visible: modelData.type === "int"
                                        from: modelData.minimum
                                        to: modelData.maximum
                                        editable: true
                                        value: win.draft[modelData.key] || modelData.default || modelData.minimum
                                        onValueModified: win.draft[modelData.key] = value
                                    }

                                    ComboBox {
                                        id: choiceBox
                                        Layout.fillWidth: true
                                        visible: modelData.type === "choice"
                                        readonly property var options: {
                                            if (modelData.type !== "choice" || !win.widget) return [""]
                                            const list = [""].concat(controller.choices(win.widget.kind, modelData.key))
                                            const current = win.draft[modelData.key] || ""
                                            return list.indexOf(current) >= 0 ? list : list.concat([current])
                                        }
                                        model: options.map(o => o === "" ? "Default" : o)
                                        currentIndex: Math.max(0, options.indexOf(win.draft[modelData.key] || ""))
                                        onActivated: index => win.draft[modelData.key] = options[index]
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: modelData.type === "secret"
                                        TextField {
                                            id: secretField
                                            Layout.fillWidth: true
                                            echoMode: TextInput.Password
                                            placeholderText: "Paste to add or replace the stored key"
                                        }
                                        Button {
                                            text: "Save to Keyring"
                                            enabled: secretField.text.trim() !== ""
                                            onClicked: {
                                                const error = controller.saveSecret(win.widget.kind, win.draft.server || "", secretField.text)
                                                secretStatus.error = error
                                                if (!error) secretField.text = ""
                                                win.secretTick++
                                            }
                                        }
                                    }
                                    Label {
                                        id: secretStatus
                                        property string error: ""
                                        visible: modelData.type === "secret"
                                        Layout.fillWidth: true
                                        wrapMode: Text.Wrap
                                        color: error ? "#d71920" : stored ? "#3c8a2e" : sys.windowText
                                        readonly property bool stored: win.secretTick >= 0 && win.widget
                                            && controller.hasSecret(win.widget.kind, win.draft.server || "")
                                        text: error ? error
                                            : !win.draft.server ? "Enter the server address first, then save the key."
                                            : stored ? "A key is stored in your keyring for this server."
                                            : "No key stored for this server yet."
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        visible: modelData.help !== ""
                                        text: modelData.help
                                        wrapMode: Text.Wrap
                                        opacity: 0.65
                                        font.pointSize: Qt.application.font.pointSize * 0.85
                                    }
                                }
                            }
                        }
                    }

                    Label { text: "Check every:"; Layout.preferredWidth: 140 }
                    SpinBox {
                        from: 5
                        to: 3600
                        stepSize: 5
                        editable: true
                        value: win.draft.interval || 60
                        onValueModified: win.draft.interval = value
                        textFromValue: (v, locale) => v + " s"
                        valueFromText: (t, locale) => parseInt(t)
                    }

                    Label { text: "Show badges:"; Layout.preferredWidth: 140; Layout.alignment: Qt.AlignTop; Layout.topMargin: 6 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: win.widget ? controller.statesFor(win.widget.kind) : []
                            CheckBox {
                                required property var modelData
                                text: modelData.label
                                checked: (win.draft.hiddenStates || []).indexOf(modelData.key) < 0
                                onToggled: {
                                    const hidden = (win.draft.hiddenStates || []).filter(k => k !== modelData.key)
                                    if (!checked) hidden.push(modelData.key)
                                    win.draft.hiddenStates = hidden
                                }
                            }
                        }
                        CheckBox {
                            text: "Also show states with nothing in them"
                            checked: !!win.draft.showZero
                            onToggled: win.draft.showZero = checked
                        }
                        CheckBox {
                            text: "Show the total, e.g. \"(of 919)\""
                            checked: !!win.draft.showTotal
                            onToggled: win.draft.showTotal = checked
                        }
                    }

                    Label { text: "Notifications:"; Layout.preferredWidth: 140 }
                    CheckBox {
                        text: "Notify me about new problems"
                        checked: win.draft.notify !== false
                        onToggled: win.draft.notify = checked
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: win.widget === null
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                text: "Pick a type on the left and click Add."
            }

            RowLayout {
                Layout.fillWidth: true
                visible: win.widget !== null
                Item { Layout.fillWidth: true }
                Button { text: "Revert"; onClicked: win.loadDraft() }
                Button {
                    text: "Save"
                    highlighted: true
                    onClicked: {
                        const index = win.selected
                        controller.saveWidget(win.widget.wid, win.draft)
                        win.selected = index
                        win.loadDraft()
                    }
                }
            }

            MenuSeparator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Label { text: "Badge style:" }
                ComboBox {
                    model: ["Square", "Rounded"]
                    currentIndex: controller.badgeStyle === "rounded" ? 1 : 0
                    onActivated: index => controller.badgeStyle = index === 1 ? "rounded" : "square"
                }
                CheckBox {
                    text: "Start at login"
                    checked: controller.startAtLogin
                    onToggled: controller.startAtLogin = checked
                }
                Item { Layout.fillWidth: true }
                Label { text: "v" + controller.version; opacity: 0.6 }
            }
        }
    }
}
