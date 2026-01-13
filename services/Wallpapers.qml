pragma Singleton

import qs.config
import qs.utils
import Caelestia.Models
import Quickshell
import Quickshell.Io
import QtQuick

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: Config.services.smartScheme ? [] : ["--no-smart"]

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string previewFramePath
    property string actualCurrent
    property bool previewColourLock

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        previewFramePath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic") {
            if (Images.isValidVideoByName(path)) {
                // For videos, extract a frame first
                extractVideoFrameForPreview(path);
            } else {
                getPreviewColoursProc.running = true;
            }
        }
    }

    function extractVideoFrameForPreview(videoPath: string): void {
        videoFrameExtractProc.videoPath = videoPath;
        videoFrameExtractProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (!previewColourLock)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: Config.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        target: "wallpaper"

        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            root.previewColourLock = false;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Media
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewFramePath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }

    Process {
        id: videoFrameExtractProc

        property string videoPath
        readonly property string outputPath: `${Paths.cache}/video_preview.png`

        command: ["ffmpeg", "-y", "-i", videoPath, "-ss", "00:00:10", "-frames:v", "1", "-q:v", "2", "-f", "image2", outputPath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Frame extracted successfully, now analyze it
                root.previewFramePath = outputPath;
                getPreviewColoursProc.running = true;
            } else {
                console.warn("Failed to extract video frame for preview");
                Colours.showPreview = false;
            }
        }
    }
}
