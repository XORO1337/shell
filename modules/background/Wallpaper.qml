pragma ComponentBehavior: Bound

import qs.components
import qs.components.images
import qs.components.filedialog
import qs.services
import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    required property var screen

    property string source: Wallpapers.current
    property Item current: one
    readonly property bool isVideo: Images.isValidVideoByName(source)

    // Expose whether video is active so Background.qml can adjust
    readonly property bool videoActive: isVideo && source

    anchors.fill: parent

    onSourceChanged: {
        if (!source) {
            current = null;
            mpvpaperProc.running = false;
        } else if (isVideo) {
            // For videos, start mpvpaper
            current = null;
            one.path = "";
            two.path = "";
            mpvpaperProc.running = true;
        } else {
            // For images, use the image crossfade system
            mpvpaperProc.running = false;
            if (current === one)
                two.update();
            else
                one.update();
        }
    }

    Component.onCompleted: {
        if (source && !isVideo)
            Qt.callLater(() => one.update());
        else if (source && isVideo)
            mpvpaperProc.running = true;
    }

    // mpvpaper process for video wallpapers
    Process {
        id: mpvpaperProc

        property list<string> mpvOptions: {
            let opts = [];
            if (Config.background.videoWallpaper.loop)
                opts.push("--loop");
            if (Config.background.videoWallpaper.muted)
                opts.push("--mute=yes");
            else
                opts.push(`--volume=${Math.round(Config.background.videoWallpaper.volume * 100)}`);
            if (Config.background.videoWallpaper.pauseOnFullscreen)
                opts.push("--pause");
            if (Config.background.videoWallpaper.hwdec)
                opts.push(`--hwdec=${Config.background.videoWallpaper.hwdec}`);
            return opts;
        }

        command: ["mpvpaper", "-o", mpvOptions.join(" "), root.screen?.name ?? "*", root.source]

        onExited: (exitCode, exitStatus) => {
            if (running && exitCode !== 0) {
                console.warn("mpvpaper exited with code:", exitCode);
            }
        }
    }

    Loader {
        anchors.fill: parent

        active: !root.source
        asynchronous: true

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Appearance.spacing.large

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.extraLarge * 5
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Appearance.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.extraLarge * 2
                        font.bold: true
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Appearance.padding.large * 2
                        implicitHeight: selectWallText.implicitHeight + Appearance.padding.small * 2

                        radius: Appearance.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image and video files")
                            filters: Images.validMediaExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary

                            function onClicked(): void {
                                dialog.open();
                            }
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font.pointSize: Appearance.font.size.large
                        }
                    }
                }
            }
        }
    }

    // Image wallpaper components (only used for static images)
    Img {
        id: one
        visible: !root.isVideo
    }

    Img {
        id: two
        visible: !root.isVideo
    }

    component Img: CachingImage {
        id: img

        property string pathInternal

        function update(): void {
            if (path === root.source)
                root.current = this;
            else
                path = root.source;
        }

        anchors.fill: parent

        opacity: 0
        scale: Wallpapers.showPreview ? 1 : 0.8

        onStatusChanged: {
            if (status === Image.Ready)
                root.current = this;
        }

        states: State {
            name: "visible"
            when: root.current === img

            PropertyChanges {
                img.opacity: 1
                img.scale: 1
            }
        }

        transitions: Transition {
            Anim {
                target: img
                properties: "opacity,scale"
            }
        }
    }
}
