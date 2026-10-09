import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support

KCM.SimpleKCM {
    id: page

    property string cfg_account

    // Accounts gh is logged in to, as {login, active}.
    property var ghAccounts: []
    readonly property string activeLogin: (ghAccounts.find(a => a.active) || {}).login || ""
    // Keep a configured account in the list even if gh has since logged it out.
    readonly property var accountChoices: {
        const logins = ghAccounts.map(a => a.login)
        return cfg_account && !logins.includes(cfg_account) ? logins.concat([cfg_account]) : logins
    }

    P5Support.DataSource {
        engine: "executable"
        connectedSources: ["gh auth status --json hosts --jq '.hosts[][] | [.login, (.active | tostring)] | @tsv'"]
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            page.ghAccounts = data["stdout"].split("\n").filter(line => line.trim()).map(line => {
                const [login, active] = line.split("\t")
                return { login: login, active: active === "true" }
            })
        }
    }
    property alias cfg_pollInterval: pollInterval.value

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("GitHub account:")
            model: [page.activeLogin ? i18n("Active gh account (%1)", page.activeLogin) : i18n("Active gh account")]
                .concat(page.accountChoices)
            currentIndex: page.cfg_account ? page.accountChoices.indexOf(page.cfg_account) + 1 : 0
            onActivated: index => page.cfg_account = index === 0 ? "" : page.accountChoices[index - 1]
        }
        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Add one widget per account to watch several. Log in to more accounts with \"gh auth login\".")
        }

        QQC2.SpinBox {
            id: pollInterval
            Kirigami.FormData.label: i18n("Check every:")
            from: 1
            to: 60
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }
    }
}
