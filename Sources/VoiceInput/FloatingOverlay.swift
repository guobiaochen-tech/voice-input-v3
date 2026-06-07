import Cocoa

/// 右上角药丸形浮动指示器（系统通知区域位置）
/// 参考 Typeoff 的 IndicatorApp.jsx 设计
class FloatingOverlay {
    static let shared = FloatingOverlay()
    private var panel: NSPanel?
    private var contentView: OverlayView?

    private init() {}

    // MARK: - 公开接口

    enum State {
        case idle
        case recording
        case thinking
    }

    func show(state: State) {
        ensurePanel()
        contentView?.setState(state)
        reposition()
        if !(panel?.isVisible ?? false) {
            panel?.orderFrontRegardless()
        }
    }

    func hide() {
        contentView?.setState(.idle)
        // 延迟隐藏以播放消失动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.contentView?.reset()
        }
    }

    func updateVolume(_ level: Float) {
        contentView?.setVolume(level)
    }

    func updateSpectrum(_ bands: [Float]) {
        contentView?.setSpectrum(bands)
    }

    func updatePartialText(_ text: String) {
        contentView?.setPartialText(text)
    }

    func updateDuration(_ seconds: TimeInterval) {
        contentView?.setDuration(seconds)
    }

    // MARK: - 窗口管理

    private func ensurePanel() {
        if panel != nil { return }

        let size = NSSize(width: 800, height: 160)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true

        let view = OverlayView(frame: NSRect(origin: .zero, size: size))
        p.contentView = view
        contentView = view
        panel = p
    }

    /// 右上角（系统通知区域位置，跟随鼠标所在屏幕）
    private func reposition() {
        guard let panel else { return }

        // 找到鼠标所在的屏幕
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }

        let sf = screen.visibleFrame
        let pw = panel.frame.width
        let ph = panel.frame.height
        let origin = NSPoint(
            x: sf.maxX - pw,
            y: sf.maxY - ph
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - 药丸形视图

private class OverlayView: NSView {
    private let container = NSView()
    private let micIcon: NSImageView = {
        let iv = NSImageView()
        iv.wantsLayer = true
        iv.imageScaling = .scaleProportionallyUpOrDown
        if let url = Bundle.main.url(forResource: "menu-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            iv.contentTintColor = .white
            iv.image = image
        }
        return iv
    }()
    private let thinkingLabel = NSTextField(labelWithString: "思考中...")
    private let timerLabel = NSTextField(labelWithString: "0:00")
    private let partialLabel = NSTextField(wrappingLabelWithString: "")
    private let progressFill = NSView()

    // 波形柱子
    private let barCount = 20
    private var barViews: [NSView] = []
    private var barHeights: [CGFloat] = []
    private var barSpeeds: [CGFloat] = []
    private var barTargetHeights: [CGFloat] = []
    private var displayLink: CVDisplayLink?
    private var lastSpectrum: [Float] = []
    private var hasSpectrum = false

    // 进度条动画
    private var thinkingStartTime: TimeInterval = 0
    private var progressDisplayLink: CVDisplayLink?

    private var currentState: FloatingOverlay.State = .idle
    private var currentDuration: TimeInterval = 0

    // 药丸尺寸
    private var _pillSize = NSSize(width: 160, height: 36)

    private let pillHeight: CGFloat = 36
    private let pillRadius: CGFloat = 18
    private let pillPadX: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // 容器（药丸）
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = pillRadius
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.3).cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.shadowColor = NSColor.shadowColor.cgColor
        container.layer?.shadowOpacity = 0.25
        container.layer?.shadowOffset = NSSize(width: 0, height: -2)
        container.layer?.shadowRadius = 8
        addSubview(container)

        // 麦克风图标（和菜单栏图标一致）
        container.addSubview(micIcon)

        // 波形柱子
        for _ in 0..<barCount {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.cgColor
            bar.layer?.cornerRadius = 1
            container.addSubview(bar)
            barViews.append(bar)
            barHeights.append(2)
            barTargetHeights.append(2)
            // 每根柱子独立速度
            barSpeeds.append(CGFloat.random(in: 0.09...0.16))
        }

        // 思考标签
        thinkingLabel.font = NSFont.systemFont(ofSize: 13)
        thinkingLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        thinkingLabel.alignment = .center
        thinkingLabel.isBezeled = false
        thinkingLabel.drawsBackground = false
        thinkingLabel.isEditable = false
        thinkingLabel.isSelectable = false
        thinkingLabel.isHidden = true
        container.addSubview(thinkingLabel)

        // 计时器
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        timerLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        timerLabel.alignment = .right
        timerLabel.isBezeled = false
        timerLabel.drawsBackground = false
        timerLabel.isEditable = false
        timerLabel.isSelectable = false
        timerLabel.isHidden = true
        container.addSubview(timerLabel)

        // Partial 文本
        partialLabel.font = NSFont.systemFont(ofSize: 13)
        partialLabel.textColor = .white
        partialLabel.alignment = .right
        partialLabel.isBezeled = false
        partialLabel.drawsBackground = false
        partialLabel.isEditable = false
        partialLabel.isSelectable = false
        partialLabel.isHidden = true
        partialLabel.lineBreakMode = .byTruncatingHead
        container.addSubview(partialLabel)

        // 进度填充（thinking 状态，整个药丸作为进度条）
        container.layer?.masksToBounds = true
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        progressFill.isHidden = true
        container.addSubview(progressFill, positioned: .below, relativeTo: thinkingLabel)

        layoutPill()
    }

    override func layout() {
        super.layout()
        layoutPill()
    }

    // MARK: - 状态切换

    func setState(_ state: FloatingOverlay.State) {
        currentState = state
        switch state {
        case .idle:
            stopWaveformAnimation()
            stopProgressAnimation()
            micIcon.isHidden = true
            thinkingLabel.isHidden = true
            timerLabel.isHidden = true
            partialLabel.isHidden = true
            progressFill.isHidden = true
            barViews.forEach { $0.isHidden = true }

        case .recording:
            stopProgressAnimation()
            thinkingLabel.isHidden = true
            progressFill.isHidden = true
            micIcon.isHidden = false
            timerLabel.isHidden = false
            partialLabel.isHidden = true
            barViews.forEach { $0.isHidden = false }
            startWaveformAnimation()
            updatePillWidth(base: 160)

        case .thinking:
            stopWaveformAnimation()
            micIcon.isHidden = true
            barViews.forEach { $0.isHidden = true }
            timerLabel.isHidden = true
            partialLabel.isHidden = true
            thinkingLabel.isHidden = false
            thinkingLabel.stringValue = "思考中..."
            progressFill.isHidden = false
            thinkingStartTime = CACurrentMediaTime()
            startProgressAnimation()
            updatePillWidth(base: 160)
        }
    }

    func reset() {
        setState(.idle)
        currentDuration = 0
        lastSpectrum = []
        hasSpectrum = false
        updatePillWidth(base: 160)
    }

    // MARK: - 数据更新

    func setVolume(_ level: Float) {
        // 兼容：如果没有频谱数据，用音量驱动
        if !hasSpectrum {
            lastSpectrum = [Float](repeating: level, count: 22)
        }
    }

    func setSpectrum(_ bands: [Float]) {
        if !bands.isEmpty {
            hasSpectrum = true
            lastSpectrum = bands
        }
    }

    func setPartialText(_ text: String) {
        guard currentState == .recording else { return }
        if text.count >= 6 {
            // 显示 partial 文本，隐藏波形
            partialLabel.isHidden = false
            partialLabel.stringValue = text
            barViews.forEach { $0.isHidden = true }
            updatePillWidth(base: min(max(350, CGFloat(text.count) * 14 + 100), 500))
        }
    }

    func setDuration(_ seconds: TimeInterval) {
        // 99:59 后清零
        let clamped = seconds.truncatingRemainder(dividingBy: 6000)
        currentDuration = clamped
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        timerLabel.stringValue = String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - 布局

    var pillSize: NSSize {
        return _pillSize
    }

    private func layoutPill() {
        let w = bounds.width
        let h = bounds.height

        // 容器靠右上角
        let pw = container.frame.width
        let ph = pillHeight
        container.frame = NSRect(x: w - pw - 16, y: h - ph - 8, width: pw, height: ph)

        let cy = (ph - 16) / 2  // 图标垂直居中（图标 16pt）

        // 麦克风图标
        micIcon.frame = NSRect(x: pillPadX, y: cy, width: 18, height: 18)

        // 波形柱子
        let barX0: CGFloat = pillPadX + 20
        let barW: CGFloat = 3
        let barGap: CGFloat = 1
        let barMaxH: CGFloat = 18
        let barY0 = (ph - barMaxH) / 2

        for (i, bar) in barViews.enumerated() {
            let x = barX0 + CGFloat(i) * (barW + barGap)
            let bh = barHeights[i]
            bar.frame = NSRect(x: x, y: barY0 + (barMaxH - bh) / 2, width: barW, height: bh)
        }

        // 计时器（右侧）
        let timerW: CGFloat = 44
        timerLabel.frame = NSRect(x: container.frame.width - pillPadX - timerW, y: cy, width: timerW, height: 16)

        // Partial 文本
        let textX: CGFloat = pillPadX + 24
        let textW = container.frame.width - textX - pillPadX - 44
        partialLabel.frame = NSRect(x: textX, y: cy - 1, width: max(textW, 0), height: 18)

        // 思考标签
        thinkingLabel.frame = NSRect(x: pillPadX, y: cy, width: container.frame.width - pillPadX * 2, height: 16)
    }

    private func updatePillWidth(base: CGFloat) {
        let w = base
        _pillSize = NSSize(width: w, height: pillHeight)
        container.frame = NSRect(x: container.frame.origin.x, y: container.frame.minY, width: w, height: pillHeight)
        layoutPill()
    }

    // MARK: - 波形动画

    private func startWaveformAnimation() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let dl = link else { return }

        CVDisplayLinkSetOutputCallback(dl, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let ptr = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<OverlayView>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { view.animateWaveform() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(dl)
        displayLink = dl
    }

    private func stopWaveformAnimation() {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
            displayLink = nil
        }
    }

    private func animateWaveform() {
        guard currentState == .recording else {
            stopWaveformAnimation()
            return
        }

        let barMaxH: CGFloat = 18
        let barMinH: CGFloat = 2

        for i in 0..<barCount {
            // 用真实频谱数据（如果有），否则用音量
            let rawLevel: CGFloat
            if i < lastSpectrum.count {
                rawLevel = CGFloat(lastSpectrum[i])
            } else if let last = lastSpectrum.last {
                rawLevel = CGFloat(last)
            } else {
                rawLevel = 0
            }

            let target = max(barMinH, rawLevel * barMaxH)

            // 平滑过渡：上升快、下降慢（衰减效果）
            if target > barTargetHeights[i] {
                barTargetHeights[i] = target
            } else {
                barTargetHeights[i] = barTargetHeights[i] * 0.85 + target * 0.15
            }

            let diff = barTargetHeights[i] - barHeights[i]
            let speed = diff > 0 ? barSpeeds[i] * 4.5 : barSpeeds[i]
            barHeights[i] += diff * speed
            barHeights[i] = max(barMinH, min(barMaxH, barHeights[i]))
        }

        // 更新柱子 frame
        let ph = pillHeight
        let barW: CGFloat = 3
        let barGap: CGFloat = 1
        let barX0: CGFloat = pillPadX + 20
        let barY0 = (ph - barMaxH) / 2

        for (i, bar) in barViews.enumerated() {
            let x = barX0 + CGFloat(i) * (barW + barGap)
            let bh = barHeights[i]
            bar.frame = NSRect(x: x, y: barY0 + (barMaxH - bh) / 2, width: barW, height: bh)
        }
    }

    // MARK: - Thinking 进度条动画

    private func startProgressAnimation() {
        guard progressDisplayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let dl = link else { return }

        CVDisplayLinkSetOutputCallback(dl, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let ptr = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<OverlayView>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { view.animateProgress() }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(dl)
        progressDisplayLink = dl
    }

    private func stopProgressAnimation() {
        if let dl = progressDisplayLink {
            CVDisplayLinkStop(dl)
            progressDisplayLink = nil
        }
    }

    private func animateProgress() {
        guard currentState == .thinking else {
            stopProgressAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - thinkingStartTime
        let progress = min(0.95, 1.0 - 1.0 / (1.0 + elapsed * 2.5))
        progressFill.frame = NSRect(x: 0, y: 0, width: container.frame.width * CGFloat(progress), height: pillHeight)
    }
}
