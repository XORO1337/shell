import Quickshell.Io

JsonObject {
    property bool enabled: true
    property DesktopClock desktopClock: DesktopClock {}
    property Visualiser visualiser: Visualiser {}
    property VideoWallpaper videoWallpaper: VideoWallpaper {}

    component DesktopClock: JsonObject {
        property bool enabled: false
    }

    component Visualiser: JsonObject {
        property bool enabled: false
        property bool autoHide: true
        property bool blur: false
        property real rounding: 1
        property real spacing: 1
    }

    component VideoWallpaper: JsonObject {
        property bool muted: true
        property bool loop: true
        property real volume: 0.5
        property bool pauseOnFullscreen: true
        property string hwdec: "auto"  // auto, vaapi, nvdec, vdpau, etc.
    }
}
