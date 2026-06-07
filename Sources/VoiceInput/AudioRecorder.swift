import AVFoundation
import Accelerate

/// 录音器：录制音频，输出 16kHz 单声道 PCM
/// 支持实时把 buffer 喂给识别器
/// 支持实时频谱分析（FFT）
class AudioRecorder {
    private let engine = AVAudioEngine()
    private var chunks: [AVAudioPCMBuffer] = []
    private(set) var isRecording = false
    private let queue = DispatchQueue(label: "com.paul.voiceinput.recorder")

    /// 频谱柱子数量
    let spectrumBandCount = 20

    /// 每收到一个 buffer 就回调（用于实时识别）
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// 音量回调，0.0~1.0
    var onVolume: ((Float) -> Void)?

    /// 频谱回调，传回每个频段的幅度 (0.0~1.0)
    var onSpectrum: (([Float]) -> Void)?

    /// 开始录音
    func start() throws {
        guard !isRecording else { return }
        chunks = []
        isRecording = true

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            // 拷贝 buffer 数据，因为底层可能复用同一块内存
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            copy.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                for ch in 0..<Int(buffer.format.channelCount) {
                    memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
                }
            }
            self.queue.sync {
                self.chunks.append(copy)
            }
            self.onBuffer?(buffer)
            self.onVolume?(self.rms(buffer))

            // 频谱分析
            let spectrum = self.computeSpectrum(from: buffer)
            self.onSpectrum?(spectrum)
        }

        try engine.start()
    }

    /// 停止录音，同时返回 Float32 samples 和可选的 WAV 文件 URL
    /// saveWav: 是否生成 WAV 文件（保存录音开关开启时传 true）
    func stopAndGetResults(saveWav: Bool = false) -> (samples: [Float], wavUrl: URL?) {
        guard isRecording else { return ([], nil) }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        var localChunks: [AVAudioPCMBuffer] = []
        queue.sync {
            localChunks = chunks
            chunks = []
        }
        guard !localChunks.isEmpty else { return ([], nil) }

        let samples = convertToFloat32Samples(localChunks)
        let wavUrl = saveWav ? convertAndWriteWav(localChunks) : nil
        return (samples, wavUrl)
    }

    /// 停止录音并返回 16kHz 单声道 Float32 采样数据（供本地 ASR 使用）
    func stopAndGetFloatSamples() -> [Float] {
        return stopAndGetResults().samples
    }

    /// 停止录音并返回 16kHz 单声道 WAV 临时文件路径
    @discardableResult
    func stop() -> URL? {
        return stopAndGetResults(saveWav: true).wavUrl
    }

    // MARK: - 音量

    private func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[0][i] * ch[0][i] }
        let level = sqrt(sum / Float(n))
        return min(level * 5.0, 1.0) // 放大并钳位
    }

    // MARK: - 频谱分析（FFT）

    /// 对音频 buffer 做 FFT，返回指定数量的频段幅度
    private func computeSpectrum(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData?[0] else {
            return [Float](repeating: 0, count: spectrumBandCount)
        }
        let frameLength = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)

        // FFT 大小：取 <= frameLength 的最大 2 的幂次
        let fftLog2n = vDSP_Length(log2(Float(frameLength)))
        let fftSize = 1 << Int(fftLog2n)
        guard fftSize >= 256 else {
            return [Float](repeating: 0, count: spectrumBandCount)
        }

        // 拷贝并 zero-pad
        var samples = [Float](repeating: 0, count: fftSize)
        let copyLen = min(frameLength, fftSize)
        for i in 0..<copyLen { samples[i] = data[i] }

        // Hanning 窗
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // 实数转 split complex（交错拆分）
        let halfSize = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)
        for i in 0..<halfSize {
            realPart[i] = windowed[2 * i]
            imagPart[i] = windowed[2 * i + 1]
        }

        // FFT
        guard let setup = vDSP_create_fftsetup(vDSP_Length(fftLog2n), FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: spectrumBandCount)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        vDSP_fft_zrip(setup, &splitComplex, 1, vDSP_Length(fftLog2n), FFTDirection(FFT_FORWARD))

        // 幅度平方
        var magnitudes = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

        // 归一化
        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfSize))

        // 分频段：80Hz ~ 8000Hz（语音主要频率范围）
        let binHz = sampleRate / Float(fftSize)
        let minBin = max(1, Int(300.0 / binHz))
        let maxBin = min(Int(8000.0 / binHz), halfSize - 1)
        let totalBins = max(1, maxBin - minBin)
        // 对数频率缩放：低频段窄、高频段宽（更接近人耳感知）
        let logMin = log(Float(minBin))
        let logMax = log(Float(maxBin))
        let binsPerBand = Float(totalBins) / Float(spectrumBandCount)

        var bands = [Float](repeating: 0, count: spectrumBandCount)
        for i in 0..<spectrumBandCount {
            // 对数缩放：每个频段在对数尺度上等宽
            let logStart = logMin + (logMax - logMin) * Float(i) / Float(spectrumBandCount)
            let logEnd = logMin + (logMax - logMin) * Float(i + 1) / Float(spectrumBandCount)
            let start = max(minBin, Int(exp(logStart)))
            let end = min(maxBin, Int(exp(logEnd)) + 1)
            var sum: Float = 0
            var count: Float = 0
            for b in start..<end {
                sum += magnitudes[b]
                count += 1
            }
            let amp = count > 0 ? sqrt(sum / count) : 0
            // 归一化 + 噪声门限：低频底噪严重，安静时归零
            let normalized = min(amp * 35.0, 1.0)
            bands[i] = normalized > 0.18 ? normalized : 0
        }

        return bands
    }

    // MARK: - 格式转换

    private func makeTargetFormat() -> AVAudioFormat {
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
    }

    /// 将 chunks 转换为 16kHz 单声道 Float32 数组
    private func convertToFloat32Samples(_ chunks: [AVAudioPCMBuffer]) -> [Float] {
        let hwFormat = engine.inputNode.outputFormat(forBus: 0)
        let targetFormat = makeTargetFormat()

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            return []
        }

        var allFrames: [Float] = []

        for buffer in chunks {
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate)
            guard frameCount > 0, let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { continue }

            var err: NSError?
            converter.convert(to: out, error: &err) { _, s in s.pointee = .haveData; return buffer }

            if let channelData = out.floatChannelData {
                let frames = Int(out.frameLength)
                for i in 0..<frames {
                    allFrames.append(channelData[0][i])
                }
            }
        }

        return allFrames
    }

    // MARK: - WAV 写入（保存录音用）

    private func convertAndWriteWav(_ chunks: [AVAudioPCMBuffer]) -> URL? {
        let hwFormat = engine.inputNode.outputFormat(forBus: 0)
        let targetFormat = makeTargetFormat()

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            return nil
        }

        var allFrames: [Float] = []

        for buffer in chunks {
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / hwFormat.sampleRate)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { continue }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if let channelData = outputBuffer.floatChannelData {
                let frames = Int(outputBuffer.frameLength)
                for i in 0..<frames {
                    allFrames.append(channelData[0][i])
                }
            }
        }

        guard !allFrames.isEmpty else { return nil }
        return writeWav(samples: allFrames)
    }

    private func writeWav(samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_input_\(Int(Date().timeIntervalSince1970)).wav")

        var pcmData = Data(capacity: samples.count * 2)
        for f in samples {
            let clamped = max(-1.0, min(1.0, f))
            let sample = Int16(clamped * 32767.0)
            pcmData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }

        let fileSize = UInt32(36 + pcmData.count)
        var header = Data(capacity: 44)
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16000).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(32000).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(pcmData.count).littleEndian) { Data($0) })

        do {
            try (header + pcmData).write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
