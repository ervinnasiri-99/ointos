import QtQuick 2.0
import calamares.slideshow 1.0

Presentation
{
    id: presentation

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.centerIn: parent
            width: 560
            height: 120
            color: "#bb42bc"   // Vivid Orchid
            radius: 8
            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Welcome to OintOS")
                font.pointSize: 24
                color: "#ffffff"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 12
            anchors.top: parent.top
            text: qsTr("A modern, stable Linux distribution for everyone.")
            font.pointSize: 14
            color: "#791f7d"   // Purple
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.centerIn: parent
            width: 560
            height: 120
            color: "#791f7d"   // Purple
            radius: 8
            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Btrfs with snapshots built in")
                font.pointSize: 22
                color: "#ffffff"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 12
            anchors.top: parent.top
            text: qsTr("Roll back any change with confidence.")
            font.pointSize: 14
            color: "#791f7d"
        }
    }
}