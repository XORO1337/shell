#include "imageanalyser.hpp"

#include <QtConcurrent/qtconcurrentrun.h>
#include <QtQuick/qquickitemgrabresult.h>
#include <qfuturewatcher.h>
#include <qimage.h>
#include <qmimedatabase.h>
#include <qprocess.h>
#include <qtemporaryfile.h>
#include <qquickwindow.h>

namespace caelestia {

ImageAnalyser::ImageAnalyser(QObject* parent)
    : QObject(parent)
    , m_futureWatcher(new QFutureWatcher<AnalyseResult>(this))
    , m_source("")
    , m_sourceItem(nullptr)
    , m_rescaleSize(128)
    , m_dominantColour(0, 0, 0)
    , m_luminance(0) {
    QObject::connect(m_futureWatcher, &QFutureWatcher<AnalyseResult>::finished, this, [this]() {
        if (!m_futureWatcher->future().isResultReadyAt(0)) {
            return;
        }

        const auto result = m_futureWatcher->result();
        if (m_dominantColour != result.first) {
            m_dominantColour = result.first;
            emit dominantColourChanged();
        }
        if (!qFuzzyCompare(m_luminance + 1.0, result.second + 1.0)) {
            m_luminance = result.second;
            emit luminanceChanged();
        }
    });
}

QString ImageAnalyser::source() const {
    return m_source;
}

void ImageAnalyser::setSource(const QString& source) {
    if (m_source == source) {
        return;
    }

    m_source = source;
    emit sourceChanged();

    if (m_sourceItem) {
        m_sourceItem = nullptr;
        emit sourceItemChanged();
    }

    requestUpdate();
}

QQuickItem* ImageAnalyser::sourceItem() const {
    return m_sourceItem;
}

void ImageAnalyser::setSourceItem(QQuickItem* sourceItem) {
    if (m_sourceItem == sourceItem) {
        return;
    }

    m_sourceItem = sourceItem;
    emit sourceItemChanged();

    if (!m_source.isEmpty()) {
        m_source = "";
        emit sourceChanged();
    }

    requestUpdate();
}

int ImageAnalyser::rescaleSize() const {
    return m_rescaleSize;
}

void ImageAnalyser::setRescaleSize(int rescaleSize) {
    if (m_rescaleSize == rescaleSize) {
        return;
    }

    m_rescaleSize = rescaleSize;
    emit rescaleSizeChanged();

    requestUpdate();
}

QColor ImageAnalyser::dominantColour() const {
    return m_dominantColour;
}

qreal ImageAnalyser::luminance() const {
    return m_luminance;
}

void ImageAnalyser::requestUpdate() {
    if (m_source.isEmpty() && !m_sourceItem) {
        return;
    }

    if (!m_sourceItem || (m_sourceItem->window() && m_sourceItem->window()->isVisible() && m_sourceItem->width() > 0 &&
                             m_sourceItem->height() > 0)) {
        update();
    } else if (m_sourceItem) {
        if (!m_sourceItem->window()) {
            QObject::connect(m_sourceItem, &QQuickItem::windowChanged, this, &ImageAnalyser::requestUpdate,
                Qt::SingleShotConnection);
        } else if (!m_sourceItem->window()->isVisible()) {
            QObject::connect(m_sourceItem->window(), &QQuickWindow::visibleChanged, this, &ImageAnalyser::requestUpdate,
                Qt::SingleShotConnection);
        }
        if (m_sourceItem->width() <= 0) {
            QObject::connect(
                m_sourceItem, &QQuickItem::widthChanged, this, &ImageAnalyser::requestUpdate, Qt::SingleShotConnection);
        }
        if (m_sourceItem->height() <= 0) {
            QObject::connect(m_sourceItem, &QQuickItem::heightChanged, this, &ImageAnalyser::requestUpdate,
                Qt::SingleShotConnection);
        }
    }
}

QImage ImageAnalyser::extractVideoFrame(const QString& videoPath) {
    // Check if ffmpeg is available
    QProcess testProcess;
    testProcess.start("which", QStringList() << "ffmpeg");
    if (!testProcess.waitForFinished(2000) || testProcess.exitCode() != 0) {
        qWarning() << "ImageAnalyser::extractVideoFrame: ffmpeg not found, cannot extract video frames";
        return QImage();
    }
    
    QTemporaryFile tempFile;
    tempFile.setFileTemplate("XXXXXX.png");
    tempFile.setAutoRemove(true);
    
    if (!tempFile.open()) {
        qWarning() << "ImageAnalyser::extractVideoFrame: Failed to create temporary file";
        return QImage();
    }
    
    const QString tempPath = tempFile.fileName();
    tempFile.close();
    
    // Use ffmpeg to extract a frame at 10 seconds (or 10% of duration, whichever is smaller)
    QProcess process;
    process.start("ffmpeg", QStringList() 
        << "-i" << videoPath
        << "-ss" << "00:00:10"  // Seek to 10 seconds
        << "-frames:v" << "1"    // Extract 1 frame
        << "-q:v" << "2"         // Quality setting
        << "-f" << "image2"      // Output format
        << tempPath
    );
    
    if (!process.waitForFinished(15000)) { // 15 second timeout
        qWarning() << "ImageAnalyser::extractVideoFrame: ffmpeg process timed out or failed:" << process.errorString();
        return QImage();
    }
    
    if (process.exitCode() != 0) {
        qWarning() << "ImageAnalyser::extractVideoFrame: ffmpeg failed with exit code:" << process.exitCode();
        qWarning() << "ffmpeg stderr:" << process.readAllStandardError();
        return QImage();
    }
    
    QImage frame(tempPath);
    if (frame.isNull()) {
        qWarning() << "ImageAnalyser::extractVideoFrame: Failed to load extracted frame";
    }
    
    return frame;
}

void ImageAnalyser::update() {
    if (m_source.isEmpty() && !m_sourceItem) {
        return;
    }

    if (m_futureWatcher->isRunning()) {
        m_futureWatcher->cancel();
    }

    if (m_sourceItem) {
        const QSharedPointer<const QQuickItemGrabResult> grabResult = m_sourceItem->grabToImage();
        QObject::connect(grabResult.data(), &QQuickItemGrabResult::ready, this, [grabResult, this]() {
            m_futureWatcher->setFuture(QtConcurrent::run(&ImageAnalyser::analyse, grabResult->image(), m_rescaleSize));
        });
    } else {
        m_futureWatcher->setFuture(QtConcurrent::run([=, this](QPromise<AnalyseResult>& promise) {
            QImage image;
            
            // Check if source is a video file
            const QMimeDatabase db;
            const QString mime = db.mimeTypeForFile(m_source).name();
            if (mime.startsWith("video/")) {
                // Extract a frame from the video
                image = extractVideoFrame(m_source);
            } else {
                // Load as regular image
                image = QImage(m_source);
            }
            
            analyse(promise, image, m_rescaleSize);
        }));
    }
}

void ImageAnalyser::analyse(QPromise<AnalyseResult>& promise, const QImage& image, int rescaleSize) {
    if (image.isNull()) {
        qWarning() << "ImageAnalyser::analyse: image is null";
        return;
    }

    QImage img = image;

    if (rescaleSize > 0 && (img.width() > rescaleSize || img.height() > rescaleSize)) {
        img = img.scaled(rescaleSize, rescaleSize, Qt::KeepAspectRatio, Qt::FastTransformation);
    }

    if (promise.isCanceled()) {
        return;
    }

    if (img.format() != QImage::Format_ARGB32) {
        img = img.convertToFormat(QImage::Format_ARGB32);
    }

    if (promise.isCanceled()) {
        return;
    }

    const uchar* data = img.bits();
    const int width = img.width();
    const int height = img.height();
    const qsizetype bytesPerLine = img.bytesPerLine();

    std::unordered_map<quint32, int> colours;
    qreal totalLuminance = 0.0;
    int count = 0;

    for (int y = 0; y < height; ++y) {
        const uchar* line = data + y * bytesPerLine;
        for (int x = 0; x < width; ++x) {
            if (promise.isCanceled()) {
                return;
            }

            const uchar* pixel = line + x * 4;

            if (pixel[3] == 0) {
                continue;
            }

            const quint32 mr = static_cast<quint32>(pixel[0] & 0xF8);
            const quint32 mg = static_cast<quint32>(pixel[1] & 0xF8);
            const quint32 mb = static_cast<quint32>(pixel[2] & 0xF8);
            ++colours[(mr << 16) | (mg << 8) | mb];

            const qreal r = pixel[0] / 255.0;
            const qreal g = pixel[1] / 255.0;
            const qreal b = pixel[2] / 255.0;
            totalLuminance += std::sqrt(0.299 * r * r + 0.587 * g * g + 0.114 * b * b);
            ++count;
        }
    }

    quint32 dominantColour = 0;
    int maxCount = 0;
    for (const auto& [colour, colourCount] : colours) {
        if (promise.isCanceled()) {
            return;
        }

        if (colourCount > maxCount) {
            dominantColour = colour;
            maxCount = colourCount;
        }
    }

    promise.addResult(qMakePair(QColor((0xFFu << 24) | dominantColour), count == 0 ? 0.0 : totalLuminance / count));
}

} // namespace caelestia
