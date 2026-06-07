import Foundation
import CommonCrypto

/// 模型管理：下载、校验、删除、测试
/// 支持多种本地 ASR 模型，每个模型可有独立的下载地址
class ModelManager {
    static let shared = ModelManager()

    private let defaultModelName = "sensevoice-small"

    let modelDir: String

    /// 下载进度回调
    typealias ProgressCallback = (_ fileName: String, _ downloaded: Int64, _ total: Int64) -> Void

    private(set) var isDownloading = false
    var downloadProgress: (downloaded: Int64, total: Int64) = (0, 0)

    private init() {
        modelDir = ensureAppDataDir() + "/models/" + defaultModelName
    }

    /// 所有支持的模型定义
    /// files: [(远程文件名, 本地文件名)] — 下载用远程名，本地存为统一名，LocalASRService 无需感知差异
    /// downloadBaseURL 为 nil 表示暂无下载源
    static let supportedModels: [(id: String, name: String, size: String, files: [(remote: String, local: String)], downloadBaseURL: String?)] = [
        ("paraformer-zh",    "Paraformer-zh",     "~243MB",
         [("model.int8.onnx", "model.onnx"), ("tokens.txt", "tokens.txt")],
         "https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main/"),
        ("whisper-small",    "Whisper Small",     "~374MB",
         [("small-encoder.int8.onnx", "encoder.onnx"), ("small-decoder.int8.onnx", "decoder.onnx"), ("small-tokens.txt", "tokens.txt")],
         "https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-small/resolve/main/"),
        ("sensevoice-small", "SenseVoice Small",  "~894MB",
         [("model.onnx", "model.onnx"), ("tokens.txt", "tokens.txt")],
         "https://file.pgyer.com/models/sensevoice-small/"),
        ("whisper-medium",   "Whisper Medium",    "~945MB",
         [("medium-encoder.int8.onnx", "encoder.onnx"), ("medium-decoder.int8.onnx", "decoder.onnx"), ("medium-tokens.txt", "tokens.txt")],
         "https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-medium/resolve/main/"),
        ("whisper-large-v3", "Whisper Large-v3",  "~1.8GB",
         [("large-v3-encoder.int8.onnx", "encoder.onnx"), ("large-v3-decoder.int8.onnx", "decoder.onnx"), ("large-v3-tokens.txt", "tokens.txt")],
         "https://hf-mirror.com/csukuangfj/sherpa-onnx-whisper-large-v3/resolve/main/"),
    ]

    private let modelsRootDir = ensureAppDataDir() + "/models"

    /// 扫描本地已有的模型
    func scanLocalModels() -> [String] {
        let fm = FileManager.default
        var available: [String] = []
        for model in Self.supportedModels {
            let dir = modelsRootDir + "/" + model.id
            let allExist = model.files.allSatisfy { fm.fileExists(atPath: dir + "/" + $0.local) }
            if allExist { available.append(model.id) }
        }
        return available
    }

    // MARK: - 状态查询

    /// 检查默认模型（sensevoice-small）是否已下载
    func isModelDownloaded() -> Bool {
        isModelDownloaded(id: defaultModelName)
    }

    /// 检查指定模型是否已下载
    func isModelDownloaded(id: String) -> Bool {
        guard let model = Self.supportedModels.first(where: { $0.id == id }) else { return false }
        let fm = FileManager.default
        let dir = modelsRootDir + "/" + id
        return model.files.allSatisfy { file in
            let path = dir + "/" + file.local
            guard fm.fileExists(atPath: path) else { return false }
            // onnx 主文件检查最小体积
            if file.local.hasSuffix(".onnx") {
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? Int else { return false }
                return size >= 50 * 1024 * 1024 // 50MB
            }
            return true
        }
    }

    struct ModelStatus {
        let downloaded: Bool
        let downloading: Bool
        let progress: (downloaded: Int64, total: Int64)
        let modelSize: Int64?
    }

    func getModelStatus() -> ModelStatus {
        var modelSize: Int64? = nil
        let modelPath = modelDir + "/model.onnx"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath),
           let size = attrs[.size] as? Int64 {
            modelSize = size
        }
        return ModelStatus(
            downloaded: isModelDownloaded(),
            downloading: isDownloading,
            progress: downloadProgress,
            modelSize: modelSize
        )
    }

    // MARK: - URL 测试

    /// 测试模型的下载地址是否可用（HEAD 请求）
    func testDownloadURL(for modelId: String) async -> Bool {
        guard let model = Self.supportedModels.first(where: { $0.id == modelId }),
              let baseURL = model.downloadBaseURL,
              let url = URL(string: baseURL + model.files[0].remote) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - 下载

    /// 下载默认模型（兼容旧调用）
    func downloadModel(onProgress: ProgressCallback? = nil) async throws {
        try await downloadModel(id: defaultModelName, onProgress: onProgress)
    }

    /// 下载指定模型
    func downloadModel(id: String, onProgress: ProgressCallback? = nil) async throws {
        guard !isDownloading else { return }
        guard let model = Self.supportedModels.first(where: { $0.id == id }),
              let baseURL = model.downloadBaseURL else {
            throw ModelError.invalidURL
        }

        isDownloading = true
        downloadProgress = (0, 0)

        defer {
            isDownloading = false
            downloadProgress = (0, 0)
        }

        let dir = modelsRootDir + "/" + id
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        for file in model.files {
            let filePath = dir + "/" + file.local

            // 跳过已存在且完整的文件
            if fm.fileExists(atPath: filePath) {
                if file.local.hasSuffix(".onnx") {
                    if let attrs = try? fm.attributesOfItem(atPath: filePath),
                       let size = attrs[.size] as? Int, size >= 50 * 1024 * 1024 {
                        NSLog("[VI-MM] 文件已存在，跳过: \(file.local)")
                        continue
                    }
                    NSLog("[VI-MM] 文件不完整，重新下载: \(file.local)")
                    try? fm.removeItem(atPath: filePath)
                } else {
                    NSLog("[VI-MM] 文件已存在，跳过: \(file.local)")
                    continue
                }
            }

            NSLog("[VI-MM] 开始下载: \(file.remote) → \(file.local)")
            try await downloadSingleFile(
                url: baseURL + file.remote,
                destPath: filePath,
                fileName: file.local,
                onProgress: onProgress
            )

            let size = (try? fm.attributesOfItem(atPath: filePath)[.size] as? Int) ?? 0
            NSLog("[VI-MM] 下载完成: \(file.local) (\(size) bytes)")
        }

        NSLog("[VI-MM] 模型 \(id) 下载全部完成")
    }

    /// 下载单个文件：手动写 .tmp，实时进度，支持重定向
    private func downloadSingleFile(
        url: String,
        destPath: String,
        fileName: String,
        onProgress: ProgressCallback?,
        redirectCount: Int = 0
    ) async throws {
        guard redirectCount <= 5 else {
            throw ModelError.httpError(-2) // too many redirects
        }

        guard let urlObj = URL(string: url) else {
            throw ModelError.invalidURL
        }

        let tempPath = destPath + ".tmp"

        // 清理旧临时文件
        try? FileManager.default.removeItem(atPath: tempPath)

        // 创建 .tmp 文件
        guard FileManager.default.createFile(atPath: tempPath, contents: nil),
              let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: tempPath)) else {
            throw ModelError.httpError(-3)
        }

        defer { try? fileHandle.close() }

        var md5 = CC_MD5_CTX()
        CC_MD5_Init(&md5)
        var totalWritten: Int64 = 0

        // 用 URLSession.bytes 逐块读取
        let (bytes, response) = try await URLSession.shared.bytes(from: urlObj)

        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(atPath: tempPath)
            throw ModelError.httpError(-1)
        }

        // 处理重定向
        if (300...399).contains(httpResponse.statusCode),
           let location = httpResponse.value(forHTTPHeaderField: "Location") {
            try? FileManager.default.removeItem(atPath: tempPath)
            try await downloadSingleFile(
                url: location, destPath: destPath, fileName: fileName,
                onProgress: onProgress, redirectCount: redirectCount + 1
            )
            return
        }

        guard httpResponse.statusCode == 200 else {
            try? FileManager.default.removeItem(atPath: tempPath)
            throw ModelError.httpError(httpResponse.statusCode)
        }

        let totalSize = httpResponse.expectedContentLength
        var lastReported: Int64 = 0
        var buffer = Data()
        let flushSize = 256 * 1024 // 256KB 写一次

        // 逐字节读取，攒到 buffer 满了写文件
        for try await byte in bytes {
            buffer.append(byte)

            if buffer.count >= flushSize {
                buffer.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress {
                        CC_MD5_Update(&md5, base, CC_LONG(buffer.count))
                    }
                }
                fileHandle.write(buffer)
                totalWritten += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                // 报告进度
                if totalWritten - lastReported >= 256 * 1024 {
                    lastReported = totalWritten
                    downloadProgress = (totalWritten, totalSize > 0 ? totalSize : 0)
                    onProgress?(fileName, totalWritten, totalSize > 0 ? totalSize : 0)
                }
            }
        }

        // 写剩余的 buffer
        if !buffer.isEmpty {
            buffer.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress {
                    CC_MD5_Update(&md5, base, CC_LONG(buffer.count))
                }
            }
            fileHandle.write(buffer)
            totalWritten += Int64(buffer.count)
        }

        // 最终进度
        downloadProgress = (totalWritten, totalSize > 0 ? totalSize : totalWritten)
        onProgress?(fileName, totalWritten, totalSize > 0 ? totalSize : totalWritten)

        try? fileHandle.close()

        // MD5 校验（通过 ETag）
        // 注意：S3 分片上传的 ETag 格式为 "hash-N"，不是标准 MD5，跳过校验
        let expectedMd5 = httpResponse.value(forHTTPHeaderField: "ETag")?
            .replacingOccurrences(of: "\"", with: "").lowercased()

        if let expected = expectedMd5, expected.count == 32, expected.allSatisfy({ $0.isHexDigit }) {
            var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&digest, &md5)
            let actualMd5 = digest.map { String(format: "%02x", $0) }.joined()
            if actualMd5 != expected {
                NSLog("[VI-MM] MD5 不匹配: 期望 \(expected) 实际 \(actualMd5)，保留文件")
            } else {
                NSLog("[VI-MM] MD5 校验通过: \(actualMd5)")
            }
        } else if let expected = expectedMd5 {
            NSLog("[VI-MM] ETag 非标准 MD5 格式 (\(expected.prefix(20))...)，跳过校验")
        }

        // .tmp → 目标文件（rename）
        try? FileManager.default.removeItem(atPath: destPath)
        do {
            try FileManager.default.moveItem(atPath: tempPath, toPath: destPath)
        } catch {
            // move 失败（跨分区），尝试 copy
            try? FileManager.default.copyItem(atPath: tempPath, toPath: destPath)
            try? FileManager.default.removeItem(atPath: tempPath)
        }
    }

    /// 计算文件的 MD5 hex
    private func md5OfFile(at path: String) -> String {
        let bufferSize = 4096
        var md5 = CC_MD5_CTX()
        CC_MD5_Init(&md5)

        guard let inputStream = InputStream(fileAtPath: path) else { return "" }
        inputStream.open()
        defer { inputStream.close() }

        while true {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            CC_MD5_Update(&md5, buffer, CC_LONG(bytesRead))
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &md5)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 删除/重下载

    /// 删除默认模型（兼容旧调用）
    func deleteModel() throws {
        try deleteModel(id: defaultModelName)
    }

    /// 删除指定模型
    func deleteModel(id: String) throws {
        guard let model = Self.supportedModels.first(where: { $0.id == id }) else { return }
        let dir = modelsRootDir + "/" + id
        let fm = FileManager.default
        for file in model.files {
            let path = dir + "/" + file.local
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
                NSLog("[VI-MM] 已删除: \(file.local)")
            }
        }
        if fm.fileExists(atPath: dir),
           let contents = try? fm.contentsOfDirectory(atPath: dir),
           contents.isEmpty {
            try? fm.removeItem(atPath: dir)
        }
    }

    func redownloadModel(onProgress: ProgressCallback? = nil) async throws {
        try deleteModel()
        try await downloadModel(onProgress: onProgress)
    }

    // MARK: - 错误

    enum ModelError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case md5Mismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "无效的下载地址"
            case .httpError(let code): "下载失败 (HTTP \(code))"
            case .md5Mismatch(let expected, let actual): "MD5 校验失败: 期望 \(expected) 实际 \(actual)"
            }
        }
    }
}
