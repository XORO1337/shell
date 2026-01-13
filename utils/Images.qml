pragma Singleton

import Quickshell

Singleton {
    readonly property list<string> validImageTypes: ["jpeg", "png", "webp", "tiff", "svg"]
    readonly property list<string> validImageExtensions: ["jpg", "jpeg", "png", "webp", "tif", "tiff", "svg"]
    readonly property list<string> validVideoExtensions: ["mp4", "mkv", "webm", "avi", "mov", "wmv", "flv", "m4v", "ogv"]
    readonly property list<string> validMediaExtensions: [...validImageExtensions, ...validVideoExtensions]

    function isValidImageByName(name: string): bool {
        return validImageExtensions.some(t => name.endsWith(`.${t}`));
    }

    function isValidVideoByName(name: string): bool {
        return validVideoExtensions.some(t => name.endsWith(`.${t}`));
    }

    function isValidMediaByName(name: string): bool {
        return validMediaExtensions.some(t => name.endsWith(`.${t}`));
    }
}
