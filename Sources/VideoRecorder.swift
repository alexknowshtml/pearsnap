import AVFoundation
import ScreenCaptureKit
import AppKit

class VideoRecorder: NSObject {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var outputURL: URL?
    private var startTime: CMTime?
    
    var onRecordingComplete: ((URL) -> Void)?
    var onRecordingError: ((Error) -> Void)?
    
    func startRecording(region: CGRect, screen: NSScreen) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "pearsnap_\(Int(Date().timeIntervalSince1970)).mov"
        outputURL = tempDir.appendingPathComponent(filename)
        
        guard let outputURL = outputURL else {
            throw NSError(domain: "VideoRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output URL"])
        }
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let display = content.displays.first(where: { display in
            NSScreen.screens.first { $0.displayID == display.displayID } == screen
        }) ?? content.displays.first else {
            throw NSError(domain: "VideoRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        
        // Create filter for the display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Configure stream
        let config = SCStreamConfiguration()
        config.width = Int(region.width) * 2  // Retina
        config.height = Int(region.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)  // 30 fps
        config.queueDepth = 5
        config.showsCursor = true
        
        // Set source rect (the region to capture)
        config.sourceRect = CGRect(
            x: region.origin.x - screen.frame.origin.x,
            y: screen.frame.height - region.origin.y - region.height + screen.frame.origin.y,
            width: region.width,
            height: region.height
        )
        
        // Setup asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        assetWriter?.add(videoInput!)
        assetWriter?.startWriting()
        
        // Create and start stream
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.pearsnap.videoqueue"))
        try await stream?.startCapture()
        
        isRecording = true
        startTime = nil
        
        return outputURL
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        
        try? await stream?.stopCapture()
        stream = nil
        
        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()
        
        if let url = outputURL {
            onRecordingComplete?(url)
        }
    }
}

extension VideoRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRecording = false
        onRecordingError?(error)
    }
}

extension VideoRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen, let videoInput = videoInput else { return }
        
        if startTime == nil {
            startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: startTime!)
        }
        
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}
