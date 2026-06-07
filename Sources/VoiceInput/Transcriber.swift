import Foundation
import AVFoundation

/// 语音转写：使用阿里云 DashScope Paraformer 实时语音识别（WebSocket 流式）
/// 所有共享状态通过 queue 串行化，满足 @unchecked Sendable
class Transcriber: @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var apiKey: String = ""
    private var taskId: String = ""

    private var completedSentences: [String] = []
    private var currentPartial: String = ""
    private var liveResult: String = ""

    /// 服务端 task-started 后才允许发送音频，之前先缓存
    private var isTaskStarted = false
    private var pendingBuffers: [Data] = []

    private var partialResultCallback: ((String) -> Void)?
    private var resultContinuation: CheckedContinuation<String?, Never>?
    private let queue = DispatchQueue(label: "com.paul.voiceinput.transcriber")

    private let logPath = ensureAppDataDir() + "/transcriber.log"

    private static let maxLogSize: Int = 1_000_000 // 1MB

    private func log(_ msg: String) {
        NSLog("[VI-T] \(msg)")
        let line = "\(Date()) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: logPath),
           let size = attrs[.size] as? Int, size > Self.maxLogSize {
            try? fm.removeItem(atPath: logPath)
        }
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    func setApiKey(_ key: String) {
        queue.sync { apiKey = key }
    }

    func setPartialResultCallback(_ callback: @escaping (String) -> Void) {
        partialResultCallback = callback
    }

    func requestAuthorization() async -> Bool {
        var key = ""
        queue.sync { key = apiKey }
        return !key.isEmpty
    }

    func loadModel(_ locale: String = "zh-CN") throws {}

    func startLiveRecognition() throws {
        var currentApiKey = ""
        queue.sync {
            currentApiKey = apiKey
            completedSentences = []
            currentPartial = ""
            liveResult = ""
            isTaskStarted = false
            pendingBuffers = []
        }
        guard !currentApiKey.isEmpty else { throw TranscribeError.notInitialized }

        let currentTaskId = UUID().uuidString.lowercased()
        queue.sync { taskId = currentTaskId }

        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        log("启动WebSocket连接, taskId=\(currentTaskId)")

        let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!
        var request = URLRequest(url: url)
        request.setValue("bearer \(currentApiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()
        queue.sync { webSocketTask = wsTask }

        receiveMessage()

        let runTask: [String: Any] = [
            "header": [
                "task_id": currentTaskId,
                "action": "run-task",
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": "paraformer-realtime-v2",
                "parameters": [
                    "sample_rate": 16000,
                    "format": "pcm",
                    "enable_inverse_text_normalization": true
                ],
                "input": [:]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: runTask)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TranscribeError.notInitialized
        }
        log("发送run-task")
        wsTask.send(.string(jsonString)) { [weak self] error in
            self?.log(error != nil ? "run-task失败: \(error!)" : "run-task已发送")
        }
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let pcmData = convertToPCM16(buffer) else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.isTaskStarted {
                self.webSocketTask?.send(.data(pcmData)) { _ in }
            } else {
                // task-started 还没到，先缓存
                self.pendingBuffers.append(pcmData)
            }
        }
    }

    /// 收到 task-started 后，一次性发送缓存的 buffer，之后直接发送
    private func flushPendingBuffers() {
        queue.sync {
            for data in pendingBuffers {
                webSocketTask?.send(.data(data)) { _ in }
            }
            pendingBuffers = []
            isTaskStarted = true
        }
    }

    func stopLiveRecognition() async -> String? {
        var currentResult = ""
        queue.sync { currentResult = liveResult }
        log("停止识别, 当前: \(currentResult.prefix(50))")

        var currentTaskId = ""
        queue.sync { currentTaskId = taskId }

        let finishTask: [String: Any] = [
            "header": [
                "task_id": currentTaskId,
                "action": "finish-task"
            ],
            "payload": [
                "input": [:]
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: finishTask),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            log("发送finish-task")
            queue.async { [weak self] in
                self?.webSocketTask?.send(.string(jsonString)) { _ in }
            }
        }

        let result = await withCheckedContinuation { continuation in
            self.queue.sync {
                self.resultContinuation = continuation
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self = self else { return }
                var latestResult = ""
                self.queue.sync { latestResult = self.liveResult }
                self.resumeContinuation(with: latestResult.isEmpty ? nil : latestResult)
            }
        }

        cleanup()
        return result
    }

    func reset() { cleanup() }

    /// 线程安全地 resume continuation（只生效一次）
    private func resumeContinuation(with result: String?) {
        queue.sync {
            guard let cont = resultContinuation else { return }
            resultContinuation = nil
            cont.resume(returning: result)
        }
    }

    // MARK: - 接收

    private func receiveMessage() {
        var ws: URLSessionWebSocketTask?
        queue.sync { ws = webSocketTask }
        guard let ws else { return }

        ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleMessage(text) }
                @unknown default: break
                }
                self.receiveMessage()
            case .failure(let error):
                self.log("WebSocket断开: \(error)")
                var wsResult = ""
                self.queue.sync { wsResult = self.liveResult }
                self.resumeContinuation(with: wsResult.isEmpty ? nil : wsResult)
            }
        }
    }

    private func handleMessage(_ text: String) {
        log("收到: \(text.prefix(200))")
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else { return }

        switch event {
        case "task-started":
            log("任务已启动")
            flushPendingBuffers()
        case "result-generated":
            handleResult(json: json)
        case "task-finished":
            var finalResult = ""
            queue.sync { finalResult = liveResult }
            log("任务完成: \(finalResult.prefix(50))")
            resumeContinuation(with: finalResult.isEmpty ? nil : finalResult)
        case "task-failed":
            let code = header["error_code"] as? String ?? ""
            let msg = header["error_message"] as? String ?? ""
            log("任务失败: \(code) \(msg)")
            var failedResult = ""
            queue.sync { failedResult = liveResult }
            resumeContinuation(with: failedResult.isEmpty ? nil : failedResult)
        default:
            log("未知事件: \(event)")
        }
    }

    private func handleResult(json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any],
              let sentence = output["sentence"] as? [String: Any] else { return }

        let text = sentence["text"] as? String ?? ""
        let sentenceEnd = sentence["sentence_end"] as? Bool ?? false

        var fullText = ""
        queue.sync {
            if sentenceEnd {
                if !text.isEmpty { completedSentences.append(text) }
                currentPartial = ""
            } else {
                currentPartial = text
            }

            fullText = completedSentences.joined() + currentPartial
            liveResult = fullText
        }
        if !fullText.isEmpty { partialResultCallback?(fullText) }
        log("识别(\(sentenceEnd ? "✓" : "…")): \(fullText.prefix(50))")
    }

    // MARK: - 音频转换

    private func convertToPCM16(_ buffer: AVAudioPCMBuffer) -> Data? {
        let hwFormat = buffer.format
        if hwFormat.sampleRate == 16000 && hwFormat.channelCount == 1 {
            return floatToPCM16(buffer)
        }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else { return nil }

        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate)
        guard frameCount > 0, let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return nil }

        var err: NSError?
        converter.convert(to: out, error: &err) { _, s in s.pointee = .haveData; return buffer }
        if err != nil { return nil }
        return floatToPCM16(out)
    }

    private func floatToPCM16(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let ch = buffer.floatChannelData else { return Data() }
        let n = Int(buffer.frameLength)
        var d = Data(capacity: n * 2)
        for i in 0..<n {
            let s = Int16(max(-1.0, min(1.0, ch[0][i])) * 32767.0)
            d.append(contentsOf: withUnsafeBytes(of: s.littleEndian) { Data($0) })
        }
        return d
    }

    private func cleanup() {
        queue.sync {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            liveResult = ""
            completedSentences = []
            currentPartial = ""
            resultContinuation = nil
            isTaskStarted = false
            pendingBuffers = []
        }
    }

    enum TranscribeError: LocalizedError {
        case notInitialized
        case unsupportedLocale
        var errorDescription: String? {
            switch self { case .notInitialized: "识别器未初始化"; case .unsupportedLocale: "不支持的语言" }
        }
    }
}
