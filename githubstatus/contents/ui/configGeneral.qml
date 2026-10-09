import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_pollInterval: pollInterval.value
    property alias cfg_notifyOnChange: notifyOnChange.checked
    property alias cfg_showOperational: showOperational.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: pollInterval
            Kirigami.FormData.label: i18n("Check every:")
            from: 1
            to: 120
            textFromValue: (value, locale) => i18np("%1 minute", "%1 minutes", value)
            valueFromText: (text, locale) => parseInt(text)
        }
        QQC2.CheckBox {
            id: notifyOnChange
            text: i18n("Notify when the overall status changes")
        }
        QQC2.CheckBox {
            id: showOperational
            text: i18n("List operational components")
        }
    }
}
