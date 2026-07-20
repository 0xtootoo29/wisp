import Cocoa
import Carbon.HIToolbox

// GPT Live 悬浮球 v0.8
// - 5 款图片皮肤（GPT-Image2 定稿）：外壳静止（高光不转）+ 内核双层反向旋转（漩涡流体感）+ 光晕呼吸
// - 右键菜单可切换球体样式（记忆选择）
// - 语音链路 v0.10：Native Messaging（App → wisp-bridge → 扩展点按钮），零 AppleScript 零轮询
//   状态由扩展 MutationObserver 实时推送；后台标签启动/零跳转特性不变

// MARK: - 皮肤定义

struct OrbSkin {
    let id: String
    let title: String
    let file: String
    let glow: NSColor
    let style: String // "swirl" 内核旋转 / "calm" 静谧呼吸（无旋转纹理的纯渐变球）
}

let SKINS: [OrbSkin] = [
    OrbSkin(id: "frost",   title: "冰雾 Frost",    file: "skin1", glow: NSColor(calibratedRed: 0.65, green: 0.80, blue: 0.97, alpha: 1), style: "swirl"),
    OrbSkin(id: "nebula",  title: "星云 Nebula",   file: "skin2", glow: NSColor(calibratedRed: 0.35, green: 0.55, blue: 1.00, alpha: 1), style: "swirl"),
    OrbSkin(id: "azure",   title: "晴空 Azure",    file: "skin3", glow: NSColor(calibratedRed: 0.47, green: 0.74, blue: 1.00, alpha: 1), style: "calm"),
    OrbSkin(id: "droplet", title: "水滴 Droplet",  file: "skin4", glow: NSColor(calibratedRed: 0.70, green: 0.89, blue: 0.98, alpha: 1), style: "swirl"),
    OrbSkin(id: "plasma",  title: "离子 Plasma",   file: "skin5", glow: NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.95, alpha: 1), style: "swirl"),
]

// MARK: - 悬浮球视图（图片皮肤 + 动效引擎）

final class OrbView: NSView {
    var onTap: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragStart: (() -> Void)?    // 按下（打断滑动动画，防止和拖拽抢写位置）
    var onRelease: (() -> Void)?      // 松手（无论点击还是拖拽，先于 onTap/onDragEnd）
    var onDragEnd: (() -> Void)?      // 拖拽松手（贴边吸附判定）
    var onHover: ((Bool) -> Void)?    // 鼠标进出（半隐浮出/缩回）

    private let glow = CAGradientLayer()  // 外圈柔光（径向渐变圆自绘，不用 CALayer shadow）
    private let orbContainer = CALayer()  // 圆形裁剪容器
    private let shell = CALayer()         // 外壳全图（含高光，永远静止）
    private let shellMask = CAGradientLayer() // shell 遮罩：swirl 挖空中心 / calm 全显
    private let innerA = CALayer()        // 内核纹理 A（顺时针）
    private let innerB = CALayer()        // 内核纹理 B（逆时针，半透明）
    private let shimmer = CAGradientLayer() // calm 风格的呼吸微光
    private(set) var state: String = "idle"
    private var skin: OrbSkin = SKINS[1]

    private let orbDiameter: CGFloat
    private var orbFrame: NSRect

    private var dragStartWindowOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var didDrag = false

    // 逐帧动画引擎（CABasicAnimation 的 rotation 在本图层结构失效，改手动驱动，确定性旋转）
    private var frameTimer: Timer?
    private var angleA: CGFloat = 0
    private var angleB: CGFloat = 0
    private var speedA: CGFloat = 0      // 弧度/秒
    private var speedB: CGFloat = 0
    private var phase: CGFloat = 0       // 呼吸相位
    private var blinkPhase: CGFloat = 0  // 闪烁相位（独立频率）
    private var glowBase: Float = 0.10   // 光晕基线
    private var glowAmp: Float = 0.04    // 光晕呼吸幅度
    private var glowRate: CGFloat = 0.9  // 呼吸角频率(rad/s)
    private var curOpacity: Float = 0.42 // 当前整球透明度
    private var targetOpacity: Float = 0.42
    private var shimmerOn = false
    private var blink = false             // 连接中：整球透明度忽明忽暗（真闪烁）
    private var blinkRate: CGFloat = 7.0  // 闪烁角频率(rad/s)
    private var breatheOpacity = false    // calm 风格：整球缓慢明暗呼吸
    private var breatheAmp: Float = 0.12

    init(frame: NSRect, orbDiameter d: CGFloat) {
        orbDiameter = d
        orbFrame = NSRect(x: (frame.width - d) / 2, y: (frame.height - d) / 2, width: d, height: d)
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        // 光晕：径向渐变圆（角落 alpha=0，零方形风险）
        // ponytail: 不用 CALayer shadow —— 空图层的 shadowPath 可能被忽略而按 bounds 画出方框
        let gd = d * 1.45
        glow.frame = NSRect(x: (frame.width - gd) / 2, y: (frame.height - gd) / 2, width: gd, height: gd)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1.0, y: 1.0)
        // locations 在 applySkin 设色时一并给：球边缘(d/2 / gd/2 ≈ 0.69)开始向外淡出
        layer?.addSublayer(glow)

        // 圆形容器
        orbContainer.frame = orbFrame
        orbContainer.cornerRadius = d / 2
        orbContainer.masksToBounds = true
        layer?.addSublayer(orbContainer)

        let full = CGRect(origin: .zero, size: orbFrame.size)

        // 图层顺序（底→顶）：innerA/innerB 旋转内核 → shell 边缘壳(中心透明) → gloss 高光
        // 关键：shell 中心必须透明,否则静止的全图会挡住底下旋转的内核。

        // 内核 A/B：全尺寸放大 1.25×(填满中心,旋转时不露空)，中心实、径向淡出到边缘
        for inner in [innerA, innerB] {
            let side = d * 1.25
            inner.frame = CGRect(x: (d - side) / 2, y: (d - side) / 2, width: side, height: side)
            let m = CAGradientLayer()
            m.type = .radial
            m.frame = CGRect(origin: .zero, size: inner.frame.size)
            m.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            m.locations = [0.0, 0.42, 0.60] // 中心实,0.6 后全透 → 只露中心漩涡,边缘让给壳
            m.startPoint = CGPoint(x: 0.5, y: 0.5)
            m.endPoint = CGPoint(x: 1.0, y: 1.0)
            inner.mask = m
            orbContainer.addSublayer(inner)
        }
        innerB.opacity = 0.5

        // 外壳：完整球图，但径向遮罩挖空中心 → 只留玻璃边缘/暗环/立体感,不遮内核
        shell.frame = full
        shell.contentsGravity = .resizeAspect
        shellMask.type = .radial
        shellMask.frame = full
        shellMask.startPoint = CGPoint(x: 0.5, y: 0.5)
        shellMask.endPoint = CGPoint(x: 1.0, y: 1.0)
        shell.mask = shellMask
        orbContainer.addSublayer(shell)

        // 顶部高光（程序画，玻璃反光——shell 挖空后原图高光丢失，这里补回）
        let gloss = CAGradientLayer()
        gloss.frame = CGRect(x: d * 0.24, y: d * 0.52, width: d * 0.52, height: d * 0.34)
        gloss.type = .radial
        gloss.colors = [NSColor.white.withAlphaComponent(0.6).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        gloss.locations = [0.0, 0.85]
        gloss.startPoint = CGPoint(x: 0.5, y: 0.55)
        gloss.endPoint = CGPoint(x: 1.0, y: 0.0)
        orbContainer.addSublayer(gloss)

        // calm 微光（仅 azure 用）
        shimmer.frame = CGRect(x: d * 0.2, y: d * 0.1, width: d * 0.6, height: d * 0.5)
        shimmer.type = .radial
        shimmer.colors = [NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        shimmer.startPoint = CGPoint(x: 0.5, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 1)
        shimmer.opacity = 0
        orbContainer.addSublayer(shimmer)

        applySkin(currentSkin())
        applyIdle()
        startFrameLoop()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 逐帧驱动
    private func startFrameLoop() {
        frameTimer?.invalidate()
        let dt: CGFloat = 1.0 / 60.0
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.angleA += self.speedA * dt
            self.angleB += self.speedB * dt
            self.phase += self.glowRate * dt
            self.blinkPhase += self.blinkRate * dt
            // opacity 平滑趋近
            if abs(self.curOpacity - self.targetOpacity) > 0.005 {
                self.curOpacity += (self.targetOpacity - self.curOpacity) * 0.12
            } else {
                self.curOpacity = self.targetOpacity
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if !self.innerA.isHidden {
                self.innerA.transform = CATransform3DMakeRotation(self.angleA, 0, 0, 1)
                self.innerB.transform = CATransform3DMakeRotation(self.angleB, 0, 0, 1)
            }
            let breath = (sin(self.phase) + 1) / 2 // 0..1
            self.glow.opacity = self.glowBase + self.glowAmp * Float(breath)
            // 整球透明度：闪烁 > 呼吸 > 平滑趋近
            if self.blink {
                let b = (sin(self.blinkPhase) + 1) / 2
                self.layer?.opacity = 0.3 + 0.7 * Float(b) // 0.3↔1.0 明显闪烁
            } else if self.breatheOpacity {
                self.layer?.opacity = self.curOpacity - self.breatheAmp + self.breatheAmp * 2 * Float(breath)
            } else {
                self.layer?.opacity = self.curOpacity
            }
            if self.shimmerOn {
                // 高光在球内游走（光在玻璃球里流动）+ 明暗呼吸 → calm 风格的"活"
                self.shimmer.opacity = Float(0.25 + 0.4 * breath)
                let cx = self.orbDiameter / 2, cy = self.orbDiameter / 2
                let r = self.orbDiameter * 0.17
                // 李萨如轨迹(非闭合圆)：更自然的游走
                self.shimmer.position = CGPoint(x: cx + r * cos(self.phase * 1.3),
                                                y: cy + r * 0.7 * sin(self.phase * 1.9))
            } else {
                self.shimmer.opacity = 0
            }
            CATransaction.commit()
        }
        RunLoop.main.add(t, forMode: .common) // .common → 拖拽/菜单弹出时仍走帧
        frameTimer = t
    }

    func currentSkin() -> OrbSkin {
        let id = UserDefaults.standard.string(forKey: "orbSkin") ?? "nebula"
        return SKINS.first { $0.id == id } ?? SKINS[1]
    }

    func applySkin(_ s: OrbSkin) {
        skin = s
        UserDefaults.standard.set(s.id, forKey: "orbSkin")
        guard let path = Bundle.main.path(forResource: s.file, ofType: "png", inDirectory: "skins"),
              let img = NSImage(contentsOfFile: path) else { return }
        var rect = CGRect(origin: .zero, size: img.size)
        let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        shell.contents = cg
        innerA.contents = cg
        innerB.contents = cg
        // 径向渐变光晕：中心段被球盖住，0.69(球边缘)向外淡出到 1.0 全透明
        glow.colors = [s.glow.withAlphaComponent(0.85).cgColor,
                       s.glow.withAlphaComponent(0.85).cgColor,
                       s.glow.withAlphaComponent(0.35).cgColor,
                       s.glow.withAlphaComponent(0.0).cgColor]
        glow.locations = [0.0, 0.66, 0.80, 1.0]
        let calm = (s.style == "calm")
        innerA.isHidden = calm
        innerB.isHidden = calm
        // swirl: shell 挖空中心露旋转内核 / calm: shell 全显完整渐变球
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if calm {
            shellMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor]
            shellMask.locations = [0.0, 1.0]
        } else {
            shellMask.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.cgColor]
            shellMask.locations = [0.0, 0.56, 0.82]
        }
        CATransaction.commit()
        setState(state) // 重放当前状态参数
    }

    func setState(_ s: String) {
        state = s
        switch s {
        case "live": applyLive()
        case "busy": applyBusy()
        default: applyIdle()
        }
    }

    // 三态 = 设置逐帧引擎参数（角速度/光晕/透明度），旋转由 frameTimer 保证
    private var swirl: Bool { skin.style == "swirl" }

    private func applyIdle() {
        // 静止态：更透明降低存在感 + 弱光晕 + 缓慢旋转(swirl)/缓慢明暗呼吸(calm)
        targetOpacity = 0.38
        speedA = swirl ? 0.105 : 0    // ~60s/圈
        speedB = swirl ? -0.074 : 0   // ~85s/圈
        glowBase = 0.05; glowAmp = 0.05
        glowRate = swirl ? 0.9 : 1.6   // calm 高光游走稍快,更有生气
        shimmerOn = !swirl
        breatheOpacity = !swirl        // azure 静止态整球缓慢呼吸
        breatheAmp = 0.10
        blink = false
        if !swirl { targetOpacity = 0.5 } // calm 稍亮,让游走高光看得见
    }

    private func applyBusy() {
        // 连接中：整球忽明忽暗闪烁（明确"正在连接"信号）+ 中速旋转
        blink = true
        blinkRate = 7.0
        breatheOpacity = false
        speedA = swirl ? 0.35 : 0
        speedB = swirl ? -0.24 : 0
        glowBase = 0.25; glowAmp = 0.12; glowRate = 5.0
        shimmerOn = !swirl
    }

    private func applyLive() {
        // 通话中：全亮高亮 + 快速旋转 + 强光晕
        blink = false
        breatheOpacity = false
        targetOpacity = 1.0
        curOpacity = 1.0               // 立即拉满,和 idle 透明态形成明确高亮对比
        speedA = swirl ? 0.70 : 0     // ~9s/圈
        speedB = swirl ? -0.48 : 0    // ~13s/圈
        glowBase = 0.45; glowAmp = 0.30; glowRate = 2.2
        shimmerOn = !swirl
        breatheOpacity_live()
    }

    // calm 风格(azure)通话态也要动：整球快呼吸代替旋转
    private func breatheOpacity_live() {
        if !swirl {
            breatheOpacity = true
            breatheAmp = 0.06
            targetOpacity = 0.95
        }
    }

    // 事件接管
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartWindowOrigin = window?.frame.origin
        dragStartMouse = NSEvent.mouseLocation
        onDragStart?()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let w = window, let o = dragStartWindowOrigin, let m0 = dragStartMouse else { return }
        let m = NSEvent.mouseLocation
        if abs(m.x - m0.x) > 3 || abs(m.y - m0.y) > 3 { didDrag = true }
        w.setFrameOrigin(NSPoint(x: o.x + m.x - m0.x, y: o.y + m.y - m0.y))
    }
    override func mouseUp(with event: NSEvent) {
        onRelease?()
        if didDrag {
            if let o = window?.frame.origin {
                UserDefaults.standard.set([o.x, o.y], forKey: "orbOrigin")
            }
            onDragEnd?()
        } else {
            onTap?()
        }
    }
    override func rightMouseUp(with event: NSEvent) { onRightClick?(event) }

    // 悬停追踪（半隐时鼠标靠近月牙 → 浮出）
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

// MARK: - 悬浮球窗口

final class OrbWindow: NSWindow {
    init(size: CGFloat) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: screen.maxX - size - 12, y: screen.minY + 12)
        if let saved = UserDefaults.standard.array(forKey: "orbOrigin") as? [Double], saved.count == 2 {
            origin = NSPoint(x: saved[0], y: saved[1])
        }
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
    }
    override var canBecomeKey: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?         // 可为 nil（用户可隐藏菜单栏图标）
    var hotKeyRef: EventHotKeyRef?
    var orbWindow: OrbWindow!
    var orbView: OrbView!
    var busyTimeout: DispatchWorkItem?
    var toggling = false

    // 引导与诊断状态
    var extensionSeen = false            // 本次运行是否收到过扩展消息（= 扩展已装且桥通）
    var lastPageState = "none"           // 最近一次页面状态（idle/live 表示已登录就绪）
    var diagPending: DispatchWorkItem?   // 诊断等待回包的超时任务
    var liveStart = Date()               // 本次通话开始时刻（面板计时）
    var panelUI: PanelUI!
    var onboardUI: OnboardUI!
    var diagUI: DiagUI!

    static let windowSize: CGFloat = 150
    static let orbSize: CGFloat = 100
    static let orbPad: CGFloat = 25       // (windowSize-orbSize)/2
    static let peek: CGFloat = 32         // 半隐时露出的月牙宽
    static let snapDist: CGFloat = 70     // 贴边吸附判定距离(球边缘距屏边≤此值即吸附)

    // 贴边半隐状态
    var dockEdge: String? {               // "left"/"right"/nil，持久化
        get { UserDefaults.standard.string(forKey: "orbDock") }
        set { if let v = newValue { UserDefaults.standard.set(v, forKey: "orbDock") }
              else { UserDefaults.standard.removeObject(forKey: "orbDock") } }
    }
    var dockRevealed = false              // 当前是浮出还是半隐
    var dragging = false                  // 拖拽进行中（冻结 hover/applyDock 等自动位移）
    var dockRect: NSRect?                 // 吸附参照屏（吸附瞬间固定；球跨内部边界滑动时不得换屏）
    var boundsTimer: Timer?               // 内容位移动画（内部边界半隐用）
    var hideWork: DispatchWorkItem?       // 延迟缩回任务（可取消）
    var slideTimer: Timer?                // 缓动滑窗计时器
    var voiceState = "idle"               // 供 dock 决策：非 idle 保持浮出
    var launchGuard = true                // 启动初期忽略 hover（防光标压在生成位误触浮出）

    static let cmdNote = Notification.Name("local.tootoo.wisp.cmd")     // App → bridge → 扩展
    static let stateNote = Notification.Name("local.tootoo.wisp.state") // 扩展 → bridge → App

    /// 深浅色偏好：system / dark / light（面板「外观」行循环切换）
    func applyThemePref() {
        switch UserDefaults.standard.string(forKey: "wispTheme") ?? "system" {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }

    func setTheme(_ pref: String) {
        UserDefaults.standard.set(pref, forKey: "wispTheme")
        applyThemePref()
        panelUI?.refresh()
        onboardUI?.refresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyThemePref()
        panelUI = PanelUI(app: self)
        onboardUI = OnboardUI(app: self)
        diagUI = DiagUI(app: self)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(bridgeState(_:)), name: Self.stateNote, object: nil)
        orbWindow = OrbWindow(size: Self.windowSize)
        orbView = OrbView(frame: NSRect(x: 0, y: 0, width: Self.windowSize, height: Self.windowSize),
                          orbDiameter: Self.orbSize)
        orbView.onTap = { [weak self] in self?.toggleVoice() }
        orbView.onRightClick = { [weak self] _ in
            guard let self else { return }
            self.panelUI.show(nearOrb: self.orbWindow)
        }
        orbView.onDragStart = { [weak self] in
            // 拖拽期间冻结一切自动位移：只有手指说了算
            // （快拖时光标会瞬间甩出视图触发 mouseExited → hover 缩回动画抢窗口 = 滑脱/弹回/抖动三症状真凶）
            guard let self else { return }
            self.dragging = true
            self.slideTimer?.invalidate(); self.slideTimer = nil
            self.boundsTimer?.invalidate(); self.boundsTimer = nil
            self.orbView.setBoundsOrigin(.zero)   // 内容位移复位，拖的永远是完整球
            self.orbView.updateTrackingAreas()
            self.hideWork?.cancel()
        }
        orbView.onRelease = { [weak self] in self?.dragging = false }
        orbView.onDragEnd = { [weak self] in self?.evaluateDock() }
        orbView.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        orbWindow.contentView = orbView
        orbWindow.orderFrontRegardless()
        // 恢复上次的贴边半隐状态
        if dockEdge != nil { applyDock(hidden: true, animated: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.launchGuard = false }

        // 菜单栏图标：14寸刘海机器上易被挤到刘海后看不见，故可关。默认显示。
        if !UserDefaults.standard.bool(forKey: "hideMenuBar") { showStatusItem() }
        registerHotkey()
        // 首次启动：弹三步安装引导
        if !UserDefaults.standard.bool(forKey: "onboardingDone") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showOnboarding() }
        }
    }

    func showStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let live = (voiceState == "live")
            button.image = NSImage(systemSymbolName: live ? "waveform.circle.fill" : "waveform.circle", accessibilityDescription: "Wisp")
            button.toolTip = "Wisp — 点击展开面板（语音：点球或 ⌥⌘V）"
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc func statusItemClicked() {
        panelUI.toggle(below: statusItem?.button)
    }

    func hideStatusItem() {
        if let s = statusItem { NSStatusBar.system.removeStatusItem(s); statusItem = nil }
    }

    func setMenuBarVisible(_ visible: Bool) {
        UserDefaults.standard.set(!visible, forKey: "hideMenuBar")
        if visible { showStatusItem() } else { hideStatusItem() }
        panelUI?.refresh()
    }

    // 旧 NSMenu 已由 PanelUI 自绘面板取代（菜单栏图标点击 / 右键球同一份）

    // MARK: 贴边半隐

    /// 球心所在屏幕的可见区（多屏各自边界）。
    /// 不能用 window.screen：半隐时窗口大部分在屏外，会返回 nil/错屏 → 双屏只认最外侧边界 + 首次拖拽被错屏拉回。
    private func dockScreen() -> NSRect {
        let c = NSPoint(x: orbWindow.frame.midX, y: orbWindow.frame.midY)
        if let s = NSScreen.screens.first(where: { NSPointInRect(c, $0.frame) }) {
            return s.visibleFrame
        }
        // 球心也在屏外（深度半隐）：取离球心最近的屏幕
        let nearest = NSScreen.screens.min { a, b in
            hypot(a.frame.midX - c.x, a.frame.midY - c.y) < hypot(b.frame.midX - c.x, b.frame.midY - c.y)
        }
        return (nearest ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 拖拽松手：球边缘贴近所在屏幕左右边 → 进入半隐；否则解除吸附
    func evaluateDock() {
        let scr = dockScreen()
        let f = orbWindow.frame
        let orbLeft = f.minX + Self.orbPad
        let orbRight = f.maxX - Self.orbPad
        if abs(orbLeft - scr.minX) < Self.snapDist {
            dockEdge = "left"
        } else if abs(scr.maxX - orbRight) < Self.snapDist {
            dockEdge = "right"
        } else {
            dockEdge = nil
            dockRect = nil
            return
        }
        dockRect = scr   // 固定参照屏：半隐滑出后球心会跨到邻屏，不能再按球心重算
        applyDock(hidden: voiceState == "idle", animated: true)
    }

    /// 计算贴边位置并滑动。hidden=true 半隐只露月牙；false 浮出全貌（仍贴边）
    /// 外侧边界：窗口滑出屏外（已验证稳定）。
    /// 内部边界（中缝，越过去是邻屏）：窗口整体钉在本屏、半隐靠内容位移——
    /// macOS「显示器使用不同空间」按窗口主体改判归属屏，窗口一越中缝就被改判到邻屏整球可见，
    /// hover 一碰又改判回来 → 两屏来回跳、点不住。窗口不动即归属权永不变，根治。
    func applyDock(hidden: Bool, animated: Bool) {
        guard let edge = dockEdge, !dragging else { return }
        let scr = dockRect ?? dockScreen()
        var y = orbWindow.frame.origin.y
        y = max(scr.minY - Self.orbPad, min(y, scr.maxY - Self.windowSize + Self.orbPad))
        dockRevealed = !hidden

        let probeX = edge == "left" ? scr.minX - 5 : scr.maxX + 5
        let isInternal = NSScreen.screens.contains {
            NSPointInRect(NSPoint(x: probeX, y: y + Self.windowSize / 2), $0.frame)
        }

        if isInternal {
            // 窗口固定：球缘正好贴中缝（主体 125/150 在本屏，归属稳定）
            let wx = edge == "left" ? scr.minX - Self.orbPad
                                    : scr.maxX - Self.windowSize + Self.orbPad
            slideTimer?.invalidate(); slideTimer = nil
            orbWindow.setFrameOrigin(NSPoint(x: wx, y: y))
            // 半隐 = 内容平移 (orbSize - peek)，被窗口边界/屏幕归属裁掉
            let shift: CGFloat = hidden ? (edge == "left" ? Self.orbSize - Self.peek
                                                          : -(Self.orbSize - Self.peek)) : 0
            slideBounds(to: shift, animated: animated)
            return
        }

        slideBounds(to: 0, animated: false)   // 离开内部边界模式时复位内容位移
        let x: CGFloat
        if edge == "right" {
            x = hidden ? scr.maxX - Self.orbPad - Self.peek
                       : scr.maxX - Self.orbPad - Self.orbSize
        } else {
            x = hidden ? scr.minX + Self.peek - Self.orbPad - Self.orbSize
                       : scr.minX - Self.orbPad
        }
        let target = NSPoint(x: x, y: y)
        if animated {
            slideWindow(to: target)
        } else {
            slideTimer?.invalidate(); slideTimer = nil
            orbWindow.setFrameOrigin(target)
        }
    }

    /// 内容位移动画（easeInOutCubic）：只动 bounds 原点，窗口纹丝不动
    func slideBounds(to targetX: CGFloat, animated: Bool) {
        boundsTimer?.invalidate(); boundsTimer = nil
        let start = orbView.bounds.origin.x
        if !animated || abs(targetX - start) < 0.5 {
            orbView.setBoundsOrigin(NSPoint(x: targetX, y: 0))
            orbView.updateTrackingAreas()
            return
        }
        let dur: CGFloat = 0.30
        var elapsed: CGFloat = 0
        let step: CGFloat = 1.0 / 60.0
        let t = Timer(timeInterval: step, repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            elapsed += step
            var p = min(elapsed / dur, 1.0)
            p = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
            self.orbView.setBoundsOrigin(NSPoint(x: start + (targetX - start) * p, y: 0))
            if elapsed >= dur {
                self.orbView.setBoundsOrigin(NSPoint(x: targetX, y: 0))
                self.orbView.updateTrackingAreas()
                tm.invalidate()
                self.boundsTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        boundsTimer = t
    }

    /// 逐帧缓动滑窗（easeInOutCubic：加速→减速到位，非匀速）
    func slideWindow(to target: NSPoint) {
        slideTimer?.invalidate()
        let start = orbWindow.frame.origin
        let dur: CGFloat = 0.30
        var elapsed: CGFloat = 0
        let step: CGFloat = 1.0 / 60.0
        let t = Timer(timeInterval: step, repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            elapsed += step
            var p = min(elapsed / dur, 1.0)
            // easeInOutCubic
            p = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
            let x = start.x + (target.x - start.x) * p
            let y = start.y + (target.y - start.y) * p
            self.orbWindow.setFrameOrigin(NSPoint(x: x, y: y))
            if elapsed >= dur { self.orbWindow.setFrameOrigin(target); tm.invalidate(); self.slideTimer = nil }
        }
        RunLoop.main.add(t, forMode: .common) // .common → 拖拽/菜单期间动画不卡
        slideTimer = t
    }

    /// 悬停：靠近月牙浮出；移开立即缩回（空闲时）。拖拽中一律忽略
    func hoverChanged(_ inside: Bool) {
        guard dockEdge != nil, !launchGuard, !dragging else { return }
        hideWork?.cancel()
        if inside {
            if !dockRevealed { applyDock(hidden: false, animated: true) }
        } else if voiceState == "idle" {
            applyDock(hidden: true, animated: true) // 移开立即收回，无延迟
        }
    }

    /// 语音状态变化联动：连接/通话中保持浮出，回到空闲后缩回
    func dockOnStateChange(_ s: String) {
        voiceState = s
        guard dockEdge != nil else { return }
        hideWork?.cancel()
        if s == "idle" {
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.dockEdge != nil, self.voiceState == "idle" else { return }
                self.applyDock(hidden: true, animated: true)
            }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
        } else if !dockRevealed {
            applyDock(hidden: false, animated: true)
        }
    }

    /// 收回右下角：滑回当前屏幕右下角（球缘距屏边仅 4pt），停 1s 再磁吸右边缘半隐
    @objc func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "orbOrigin")
        dockEdge = nil
        dockRect = nil
        hideWork?.cancel()
        let screen = dockScreen()
        // 球的可见右缘 = frame.maxX - orbPad → 贴边只留 4pt
        slideWindow(to: NSPoint(x: screen.maxX - Self.windowSize + Self.orbPad - 4,
                                y: screen.minY + 12))
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.voiceState == "idle" else { return }
            self.dockEdge = "right"
            self.dockRect = screen
            self.applyDock(hidden: true, animated: true)
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    @objc func quit() { NSApp.terminate(nil) }

    func postCmd(_ cmd: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.cmdNote, object: cmd, userInfo: nil, deliverImmediately: true)
    }

    /// 点球/热键：向扩展发 toggle，后续状态全靠扩展实时推送
    @objc func toggleVoice() {
        guard !toggling else { return }
        toggling = true
        applyVoiceState("busy")
        postCmd("toggle")
        // 兜底：Chrome 没开 / 扩展没装 → 无回包，45s 后回 idle
        // （扩展正常时最坏路径 = 后台开新标签 20s + 语音连接，45s 足够覆盖）
        busyTimeout?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.toggling else { return }
            self.applyVoiceState("idle")
        }
        busyTimeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: w)
    }

    @objc func bridgeState(_ note: Notification) {
        let s = (note.object as? String) ?? ""
        DispatchQueue.main.async { self.handleBridgeEvent(s) }
    }

    /// 桥上事件分流：语音三态改球；hello/status-* 是引导与诊断信号，不碰球
    func handleBridgeEvent(_ s: String) {
        switch s {
        case "idle", "busy", "live":
            extensionSeen = true
            if s != "busy" { lastPageState = s }
            applyVoiceState(s)
            refreshOnboarding(activate: false)
        case "hello":
            extensionSeen = true
            refreshOnboarding(activate: true) // 刚装好扩展 → 引导窗第②步打勾并跳回前台
        case let x where x.hasPrefix("status-"):
            extensionSeen = true
            let r = String(x.dropFirst("status-".count))
            if r != "none" && r != "unready" { lastPageState = r }
            refreshOnboarding(activate: false)
            if diagPending != nil {
                diagPending?.cancel(); diagPending = nil
                showDiag(chrome: true, report: r)
            }
        default:
            break
        }
    }

    func applyVoiceState(_ s: String) {
        switch s {
        case "live":
            if voiceState != "live" { liveStart = Date() }
            busyTimeout?.cancel()
            toggling = false
            orbView.setState("live")
            dockOnStateChange("live")
            statusItem?.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "live")
        case "busy":
            orbView.setState("busy")
            dockOnStateChange("busy")
        default: // idle / 失败
            busyTimeout?.cancel()
            toggling = false
            orbView.setState("idle")
            dockOnStateChange("idle")
            statusItem?.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "idle")
        }
        panelUI?.refresh()
    }

    /// 连接中取消：本地回 idle（若稍后真的连上，扩展的 live 推送会再纠正）
    func cancelConnect() {
        busyTimeout?.cancel()
        toggling = false
        applyVoiceState("idle")
    }

    // MARK: 三步安装引导（视觉在 WispUI.swift / OnboardUI）

    @objc func showOnboarding() {
        postCmd("status")   // 主动问一遍当前状态（老用户重开引导直接全勾）
        onboardUI.show()
    }

    /// 三步勾选刷新。activate=true 时（扩展刚装好握手）把引导窗拉回前台
    func refreshOnboarding(activate: Bool) {
        onboardUI.refresh()
        if activate, onboardUI.isVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openStore() {
        NSWorkspace.shared.open(URL(string: "https://chromewebstore.google.com/detail/mghelpfopaeahcpdgjnbffnmkeapgpnn")!)
    }
    @objc func setupTab() { postCmd("setup-tab") }

    // MARK: 诊断：为什么用不了？

    @objc func runDiagnostics() {
        let chrome = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
        postCmd("status")
        diagPending?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.diagPending = nil
            self?.showDiag(chrome: chrome, report: nil) // 2s 无回包 = 扩展没装/Chrome 没开
        }
        diagPending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    func showDiag(chrome: Bool, report: String?) {
        diagUI.show(chrome: chrome, report: report)
    }

    func registerHotkey() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.toggleVoice() }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4750_5456), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(optionKey | cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

@main
enum WispMain {
    static var delegate: AppDelegate?   // NSApplication.delegate 是弱引用，这里持有
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
