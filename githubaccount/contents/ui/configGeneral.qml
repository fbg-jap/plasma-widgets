import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_pollInterval: pollInterval.value
    property alias cfg_notifyOnNew: notifyOnNew.checked
    property alias cfg_showRepos: showRepos.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: pollInterval
            Kirigami.FormData.label: i18n("Check every:")
            from: 1
            to: 60
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }
        QQC2.CheckBox {
            id: notifyOnNew
            text: i18n("Desktop notification for new GitHub notifications")
        }
        QQC2.CheckBox {
            id: showRepos
            text: i18n("Show CI status of recently pushed repositories")
        }
    }
}
