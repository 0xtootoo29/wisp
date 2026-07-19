import Cocoa

// WispUI — 设计稿移植（wisp-design.html + wisp-orb-reference.html）
// 三界面：菜单栏下拉面板 / 三步安装引导窗 / 诊断结果弹窗
// 全部尺寸为设计稿 pt 原值；色值来自 tokens 总表（深/浅两套跟随系统）。

// MARK: - 基础工具

extension NSColor {
    convenience init(hex: UInt32, a: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }
}

final class VFlip: NSView {
    override var isFlipped: Bool { true }
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

func wLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                  : NSFont.systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.sizeToFit()
    return l
}

// MARK: - 主题 tokens（设计稿第四节总表）

struct WTheme {
    let panel0, panel1, coverA, coverB: NSColor
    let glass, btnSec, stroke, sep: NSColor
    let tx1, tx2, tx3: NSColor
    let acc, accA, accB: NSColor
    let ok, warn, err, endA, endB: NSColor
    let hover, coverGlow, chrome, tick: NSColor

    static let dark = WTheme(
        panel0: NSColor(hex: 0x070F26), panel1: NSColor(hex: 0x0C1A3C),
        coverA: NSColor(hex: 0x16306E), coverB: NSColor(hex: 0x0A1633),
        glass: NSColor(hex: 0xA6C8FA, a: 0.06), btnSec: NSColor(hex: 0xA6C8FA, a: 0.10),
        stroke: NSColor(hex: 0xBAD7F7, a: 0.14), sep: NSColor(hex: 0xBAD7F7, a: 0.12),
        tx1: NSColor(hex: 0xEAF0FD, a: 0.95), tx2: NSColor(hex: 0xC6D3EC, a: 0.60), tx3: NSColor(hex: 0xC6D3EC, a: 0.38),
        acc: NSColor(hex: 0x4E8DFF), accA: NSColor(hex: 0x5E9AFF), accB: NSColor(hex: 0x2E63E8),
        ok: NSColor(hex: 0x46C586), warn: NSColor(hex: 0xE5B45E), err: NSColor(hex: 0xE5685F),
        endA: NSColor(hex: 0xDC6C62), endB: NSColor(hex: 0xBB4A42),
        hover: NSColor(hex: 0x8CB4FF, a: 0.12), coverGlow: NSColor(hex: 0x5E9AFF, a: 0.32),
        chrome: NSColor(hex: 0x0D1C40), tick: NSColor(hex: 0xBEDCFF, a: 0.9))

    static let light = WTheme(
        panel0: NSColor(hex: 0xEFF5FD), panel1: NSColor(hex: 0xFBFDFF),
        coverA: NSColor(hex: 0xFFFFFF), coverB: NSColor(hex: 0xE3EEFC),
        glass: NSColor(hex: 0xFFFFFF, a: 0.65), btnSec: NSColor(hex: 0x153C8C, a: 0.07),
        stroke: NSColor(hex: 0x12367D, a: 0.12), sep: NSColor(hex: 0x152140, a: 0.10),
        tx1: NSColor(hex: 0x152140), tx2: NSColor(hex: 0x152140, a: 0.58), tx3: NSColor(hex: 0x152140, a: 0.36),
        acc: NSColor(hex: 0x2E6BF0), accA: NSColor(hex: 0x4E8DFF), accB: NSColor(hex: 0x2B5FE3),
        ok: NSColor(hex: 0x1F9D63), warn: NSColor(hex: 0xB9812A), err: NSColor(hex: 0xD84C43),
        endA: NSColor(hex: 0xD96A61), endB: NSColor(hex: 0xC04740),
        hover: NSColor(hex: 0x2E6BF0, a: 0.09), coverGlow: NSColor(hex: 0x4E8DFF, a: 0.20),
        chrome: NSColor(hex: 0xF7FAFE), tick: NSColor(hex: 0x2E6BF0, a: 0.55))

    static var current: WTheme {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .dark : .light
    }
}

// MARK: - 发光小球（参照稿七层构造，CSS y 坐标已翻转为 AppKit y-up）

final class GlassOrbView: NSView {
    private var glows: [CAGradientLayer] = []
    let d: CGFloat

    init(diameter: CGFloat, withNebula: Bool = true) {
        d = diameter
        super.init(frame: NSRect(x: 0, y: 0, width: d, height: d))
        wantsLayer = true
        layer?.masksToBounds = false
        let s = d / 52.0

        // ① 外光晕 ×3（径向渐变圆，非 shadow —— 空层 shadowPath 有按 bounds 画方框前科）
        for (blur, color, a) in [(8.0, 0x78AAFF, 0.55), (20.0, 0x5E9AFF, 0.38), (45.0, 0x466EF0, 0.20)] {
            let r = d / 2 + CGFloat(blur) * s * 1.2
            let g = CAGradientLayer()
            g.type = .radial
            g.frame = NSRect(x: d / 2 - r, y: d / 2 - r, width: r * 2, height: r * 2)
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1.0, y: 1.0)
            let edge = (d / 2) / r
            g.colors = [NSColor(hex: UInt32(color), a: a).cgColor,
                        NSColor(hex: UInt32(color), a: a).cgColor,
                        NSColor(hex: UInt32(color), a: 0).cgColor]
            g.locations = [0, NSNumber(value: Double(edge) * 0.92), 1]
            layer?.addSublayer(g)
            glows.append(g)
        }

        // 圆形裁剪容器（② 之后各层都在里面）
        let ball = CALayer()
        ball.frame = bounds
        ball.cornerRadius = d / 2
        ball.masksToBounds = true
        layer?.addSublayer(ball)
        let full = bounds

        // ② 核心径向渐变：中心 css(0.50,0.46) → appkit(0.50,0.54)，半径 0.5d
        ball.addSublayer(radial(full, cx: 0.50, cy: 0.54, r: 0.5, stops: [
            (0.00, NSColor(hex: 0xEAF4FF)), (0.22, NSColor(hex: 0x9CC4FF)),
            (0.48, NSColor(hex: 0x4E8DFF)), (0.76, NSColor(hex: 0x1E4FBC)), (1.00, NSColor(hex: 0x0B2A75))]))

        // ④ 底部反照：css(0.62,0.78) → appkit(0.62,0.22)，r 0.42
        ball.addSublayer(radial(full, cx: 0.62, cy: 0.22, r: 0.42, stops: [
            (0, NSColor(hex: 0x8CBEFF, a: 0.55)), (1, NSColor(hex: 0x8CBEFF, a: 0))]))

        // ⑤ 星云漩涡（两团 + 弧脊，隐约 S 形）
        if withNebula {
            ball.addSublayer(nebulaBlob(cx: 0.45, cyCss: 0.27, rx: 0.29, ry: 0.17, a: 0.85))
            ball.addSublayer(nebulaBlob(cx: 0.59, cyCss: 0.73, rx: 0.27, ry: 0.15, a: 0.70))
            let arc = CAShapeLayer()
            arc.frame = full
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 0.5 * d, y: 0.55 * d), radius: 0.33 * d,
                     startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
            arc.path = p
            arc.strokeColor = NSColor(hex: 0xFFFFFF, a: 0.55).cgColor
            arc.fillColor = nil
            arc.lineWidth = max(1.5 * s, 0.8)
            arc.lineCap = .round
            arc.setAffineTransform(CGAffineTransform(rotationAngle: 32 * .pi / 180))
            ball.addSublayer(arc)
        }

        // ③ 顶部高光：css(0.34,0.26) → appkit(0.34,0.74)，r 0.26
        ball.addSublayer(radial(full, cx: 0.34, cy: 0.74, r: 0.26, stops: [
            (0, NSColor(hex: 0xFFFFFF, a: 0.95)), (1, NSColor(hex: 0xFFFFFF, a: 0))]))

        // ⑥ 内发光（边缘白圈）+ 底部内影
        ball.addSublayer(radial(full, cx: 0.5, cy: 0.5, r: 0.5, stops: [
            (0, NSColor(hex: 0xFFFFFF, a: 0)), (0.82, NSColor(hex: 0xFFFFFF, a: 0)),
            (0.94, NSColor(hex: 0xFFFFFF, a: 0.16)), (1, NSColor(hex: 0xFFFFFF, a: 0.35))]))
        let bot = CAGradientLayer()
        bot.frame = full
        bot.startPoint = CGPoint(x: 0.5, y: 0)
        bot.endPoint = CGPoint(x: 0.5, y: 0.45)
        bot.colors = [NSColor(hex: 0x08143C, a: 0.35).cgColor, NSColor(hex: 0x08143C, a: 0).cgColor]
        ball.addSublayer(bot)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func radial(_ frame: CGRect, cx: CGFloat, cy: CGFloat, r: CGFloat,
                        stops: [(Double, NSColor)]) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.frame = frame
        g.startPoint = CGPoint(x: cx, y: cy)
        g.endPoint = CGPoint(x: cx + r, y: cy + r)
        g.colors = stops.map { $0.1.cgColor }
        g.locations = stops.map { NSNumber(value: $0.0) }
        return g
    }

    private func nebulaBlob(cx: CGFloat, cyCss: CGFloat, rx: CGFloat, ry: CGFloat, a: CGFloat) -> CALayer {
        let cy = 1 - cyCss
        let g = CAGradientLayer()
        g.type = .radial
        g.frame = NSRect(x: (cx - rx) * d, y: (cy - ry) * d, width: rx * 2 * d, height: ry * 2 * d)
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1.0, y: 1.0)
        g.colors = [NSColor(hex: 0xFFFFFF, a: a).cgColor, NSColor(hex: 0xFFFFFF, a: 0).cgColor]
        g.locations = [0, 0.72]
        g.setAffineTransform(CGAffineTransform(rotationAngle: 28 * .pi / 180))
        return g
    }

    /// 呼吸（通话中）：外光晕 3.4s ease-in-out 往返
    func setBreathing(_ on: Bool) {
        for g in glows {
            g.removeAnimation(forKey: "breath")
            if on {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 0.66; a.toValue = 1.25
                a.duration = 1.7
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                g.add(a, forKey: "breath")
            } else {
                g.opacity = 1
            }
        }
    }
}

// MARK: - 声波刻度环（48 根 1×4pt，R38，三态 calm / arc / wave）

final class TickRingView: NSView {
    private var ticks: [CALayer] = []
    private var timer: Timer?
    private var phase: CGFloat = 0
    private let R: CGFloat
    private let s: CGFloat
    var mode = "calm" { didSet { modeChanged() } }

    init(radius: CGFloat = 38, scale: CGFloat = 1, tint: NSColor) {
        R = radius; s = scale
        let side = (radius + 12) * 2
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        layer?.masksToBounds = false
        let c = side / 2
        for i in 0..<48 {
            let t = CALayer()
            t.backgroundColor = tint.cgColor
            t.bounds = CGRect(x: 0, y: 0, width: 1 * s, height: 4 * s)
            t.cornerRadius = 0.5 * s
            let a = CGFloat(i) / 48 * 2 * .pi
            t.position = CGPoint(x: c + sin(a) * R, y: c + cos(a) * R)
            t.setAffineTransform(CGAffineTransform(rotationAngle: -a))
            t.opacity = 0.30
            layer?.addSublayer(t)
            ticks.append(t)
        }
    }

    private func modeChanged() {
        timer?.invalidate(); timer = nil
        if mode == "calm" {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for t in ticks { t.opacity = 0.30; t.bounds.size.height = 4 * s }
            CATransaction.commit()
            return
        }
        let tm = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    private func step() {
        phase += 1.0 / 30.0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if mode == "arc" {
            // 9 根亮弧顺时针流动，1.8s 一圈
            let head = phase / 1.8 * 48
            for (i, t) in ticks.enumerated() {
                let dist = (CGFloat(i) - head).truncatingRemainder(dividingBy: 48)
                let j = dist < 0 ? dist + 48 : dist
                if j < 9 {
                    let f = 1 - abs(j - 4) / 5
                    t.opacity = Float(0.25 + 0.75 * f)
                    t.bounds.size.height = (4 + 2 * f) * s
                } else {
                    t.opacity = 0.20
                    t.bounds.size.height = 4 * s
                }
            }
        } else { // wave（ponytail: 相位驱动伪音量；接真实音量包络时换 v 的来源）
            for (i, t) in ticks.enumerated() {
                let v = abs(sin(CGFloat(i) * 0.85 + phase * 2.4))
                t.opacity = Float(0.45 + 0.50 * v)
                t.bounds.size.height = (3 + 7 * v) * s
            }
        }
        CATransaction.commit()
    }

    deinit { timer?.invalidate() }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 渐变按钮

final class WButton: NSView {
    enum Style { case primary, secondary, end, ghost }
    var onClick: (() -> Void)?
    private let grad = CAGradientLayer()
    private let label: NSTextField

    init(_ title: String, style: Style, w: CGFloat, h: CGFloat, fontSize: CGFloat, radius: CGFloat, theme: WTheme) {
        label = wLabel(title, size: fontSize, weight: .medium, color: .white)
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        grad.frame = bounds
        grad.cornerRadius = radius
        switch style {
        case .primary:
            grad.colors = [theme.accA.cgColor, theme.accB.cgColor]
            grad.startPoint = CGPoint(x: 0.5, y: 1); grad.endPoint = CGPoint(x: 0.5, y: 0)
            layer?.shadowColor = theme.accB.cgColor
            layer?.shadowOpacity = 0.35; layer?.shadowRadius = 8; layer?.shadowOffset = CGSize(width: 0, height: -3)
        case .end:
            grad.colors = [theme.endA.cgColor, theme.endB.cgColor]
            grad.startPoint = CGPoint(x: 0.5, y: 1); grad.endPoint = CGPoint(x: 0.5, y: 0)
            layer?.shadowColor = theme.endB.cgColor
            layer?.shadowOpacity = 0.30; layer?.shadowRadius = 8; layer?.shadowOffset = CGSize(width: 0, height: -3)
        case .secondary:
            grad.colors = [theme.btnSec.cgColor, theme.btnSec.cgColor]
            grad.borderWidth = 1; grad.borderColor = theme.stroke.cgColor
            label.textColor = theme.acc
        case .ghost:
            grad.colors = [theme.btnSec.cgColor, theme.btnSec.cgColor]
            grad.borderWidth = 1; grad.borderColor = theme.stroke.cgColor
            label.textColor = theme.tx1
        }
        layer?.addSublayer(grad)
        addSubview(label)
        label.setFrameOrigin(NSPoint(x: (w - label.frame.width) / 2, y: (h - label.frame.height) / 2))
    }

    func retitle(_ t: String) {
        label.stringValue = t
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: (frame.width - label.frame.width) / 2, y: (frame.height - label.frame.height) / 2))
    }

    override func mouseDown(with event: NSEvent) { alphaValue = 0.75 }
    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 菜单行（hover 高亮 + 左侧主色条）

final class WMenuRow: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let hoverBar = NSView()
    private let bg = NSView()
    private let theme: WTheme

    init(w: CGFloat, title: String, checked: Bool, chevron: Bool, theme: WTheme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 22))
        wantsLayer = true
        bg.frame = bounds; bg.wantsLayer = true
        bg.layer?.backgroundColor = .clear
        addSubview(bg)
        hoverBar.frame = NSRect(x: 0, y: 0, width: 1.5, height: 22)
        hoverBar.wantsLayer = true
        hoverBar.layer?.backgroundColor = theme.acc.cgColor
        hoverBar.isHidden = true
        addSubview(hoverBar)
        let ck = wLabel(checked ? "✓" : "", size: 12, weight: .semibold, color: theme.acc)
        ck.frame = NSRect(x: 12, y: (22 - ck.frame.height) / 2, width: 16, height: ck.frame.height)
        addSubview(ck)
        let t = wLabel(title, size: 13, weight: .regular, color: theme.tx1)
        t.setFrameOrigin(NSPoint(x: 28, y: (22 - t.frame.height) / 2))
        addSubview(t)
        if chevron {
            let c = wLabel("›", size: 13, weight: .regular, color: theme.tx3)
            c.setFrameOrigin(NSPoint(x: w - 12 - c.frame.width, y: (22 - c.frame.height) / 2))
            addSubview(c)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        bg.layer?.backgroundColor = theme.hover.cgColor
        hoverBar.isHidden = false
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        bg.layer?.backgroundColor = .clear
        hoverBar.isHidden = true
        onHover?(false)
    }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 圆角面板容器（渐变底 + 1px 内描边）

func panelBackdrop(w: CGFloat, h: CGFloat, radius: CGFloat, theme: WTheme) -> VFlip {
    let v = VFlip(frame: NSRect(x: 0, y: 0, width: w, height: h))
    v.wantsLayer = true
    // 圆角裁剪放在容器视图层：子视图（封面渐变/光晕）一并被裁进圆角，
    // 绕开 flipped 视图下 maskedCorners 语义翻转的坑
    v.layer?.cornerRadius = radius
    v.layer?.masksToBounds = true
    v.layer?.borderWidth = 1
    v.layer?.borderColor = theme.stroke.cgColor
    let g = CAGradientLayer()
    g.frame = v.bounds
    g.colors = [theme.panel1.cgColor, theme.panel0.cgColor]
    g.startPoint = CGPoint(x: 0.5, y: 1); g.endPoint = CGPoint(x: 0.5, y: 0)
    v.layer?.addSublayer(g)
    return v
}

// MARK: - 菜单栏下拉面板

final class PanelUI {
    weak var app: AppDelegate?
    private var panel: NSPanel?
    private var flyout: NSPanel?
    private var monitors: [Any] = []
    private var secTimer: Timer?
    private var flyoutCloseWork: DispatchWorkItem?
    private var flyoutKind: String?
    private static let coverH: CGFloat = 221   // 16顶+100环区+10+21状态+6+15副文+12+28按钮+13底
    private static let styleRowY = coverH + 5  // 「球体样式」行顶（flipped 坐标）；「外观」行 = +22

    init(app: AppDelegate) { self.app = app }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(below button: NSStatusBarButton?) {
        if isVisible { close(); return }
        guard let button, let bw = button.window else { return }
        let f = bw.frame
        show(anchor: NSPoint(x: f.midX, y: f.minY), preferBelow: true)   // 顶边贴住菜单栏，无间隙
    }

    /// 右键悬浮球：在球旁展开
    func show(nearOrb orbWindow: NSWindow) {
        if isVisible { close() }
        let f = orbWindow.frame
        show(anchor: NSPoint(x: f.midX, y: f.maxY - 20), preferBelow: false)
    }

    private func show(anchor: NSPoint, preferBelow: Bool) {
        let theme = WTheme.current
        let content = buildContent(theme: theme)
        let p = NSPanel(contentRect: content.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = content
        let scr = NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.x - content.frame.width / 2
        x = max(scr.minX + 8, min(x, scr.maxX - content.frame.width - 8))
        var y = preferBelow ? anchor.y - content.frame.height : anchor.y
        y = max(scr.minY + 8, min(y, scr.maxY - content.frame.height))   // 顶部不留边距（贴菜单栏）
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.orderFrontRegardless()
        panel = p
        installMonitors()
        // 通话中每秒刷新计时
        secTimer?.invalidate()
        if app?.voiceState == "live" {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(t, forMode: .common)
            secTimer = t
        }
    }

    func refresh() {
        guard let p = panel, p.isVisible else { return }
        let top = p.frame.maxY
        let theme = WTheme.current
        let content = buildContent(theme: theme)
        p.setFrame(NSRect(x: p.frame.minX, y: top - content.frame.height,
                          width: content.frame.width, height: content.frame.height), display: true)
        p.contentView = content
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        secTimer?.invalidate(); secTimer = nil
        closeFlyout()
        panel?.orderOut(nil)
        panel = nil
    }

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] ev in
            guard let self else { return ev }
            if ev.window != self.panel && ev.window != self.flyout { self.close() }
            return ev
        }) { monitors.append(m) }
    }

    // 面板内容：封面（球 + 环 + 状态 + 主按钮）+ 菜单区
    private func buildContent(theme: WTheme) -> VFlip {
        let W: CGFloat = 300
        let state = app?.voiceState ?? "idle"

        // 菜单行（方案 A：个性化 4 行 | 分隔线 | 帮助 2 行 | 分隔线 | 退出）
        // 前三行统一为飞出子菜单，勾选状态全部收进子菜单表达
        let rows: [(String, Bool, Bool, () -> Void)] = [
            ("球体样式", false, true, { [weak self] in self?.toggleFlyout("skin") }),
            ("外观", false, true, { [weak self] in self?.toggleFlyout("theme") }),
            ("菜单栏图标", false, true, { [weak self] in self?.toggleFlyout("menubar") }),
            ("收回右下角", false, false, { [weak self] in self?.app?.resetPosition(); self?.close() }),
            ("安装引导", false, false, { [weak self] in self?.close(); self?.app?.showOnboarding() }),
            ("诊断：为什么用不了？", false, false, { [weak self] in self?.close(); self?.app?.runDiagnostics() }),
            ("退出 Wisp", false, false, { self.app?.quit() }),
        ]
        let coverH = Self.coverH
        let menuH: CGFloat = 183    // 5 + 22×4 + 9 + 22×2 + 9 + 22 + 6
        let H = coverH + menuH
        let root = panelBackdrop(w: W, h: H, radius: 12, theme: theme)

        // ---- 封面 ----
        let cover = VFlip(frame: NSRect(x: 0, y: 0, width: W, height: coverH))
        cover.wantsLayer = true
        let cg = CAGradientLayer()
        cg.frame = cover.bounds
        cg.colors = [theme.coverA.cgColor, theme.coverB.cgColor]
        cg.startPoint = CGPoint(x: 0.5, y: 1); cg.endPoint = CGPoint(x: 0.5, y: 0)
        cover.layer?.addSublayer(cg)   // 圆角由 root 容器统一裁剪
        // （原「封面顶部主色光」层已删：矩形 frame 底边会在标题处露出硬边界，球体自带光晕已足够）
        root.addSubview(cover)

        // 球 + 刻度环（52pt 球 / R38 环）
        let orbArea = NSView(frame: NSRect(x: (W - 100) / 2, y: 16, width: 100, height: 100))
        let ring = TickRingView(radius: 38, scale: 1, tint: theme.tick)
        ring.setFrameOrigin(NSPoint(x: (100 - ring.frame.width) / 2, y: (100 - ring.frame.height) / 2))
        ring.mode = state == "busy" ? "arc" : (state == "live" ? "wave" : "calm")
        orbArea.addSubview(ring)
        let orb = GlassOrbView(diameter: 52)
        orb.setFrameOrigin(NSPoint(x: 24, y: 24))
        orb.setBreathing(state == "live")
        orbArea.addSubview(orb)
        cover.addSubview(orbArea)

        // 状态文案
        let title: String
        let sub: String
        switch state {
        case "busy": title = "正在连接…"; sub = "正在唤醒 ChatGPT 标签页"
        case "live":
            let sec = Int(Date().timeIntervalSince(app?.liveStart ?? Date()))
            title = String(format: "通话中 · %02d:%02d", sec / 60, sec % 60)
            sub = "正在聆听 · 可随时开口打断"
        default: title = "Wisp 就绪"; sub = "点击悬浮球，或按 ⌥⌘V 开始对话"
        }
        let t1 = wLabel(title, size: 15, weight: .semibold, color: theme.tx1, mono: state == "live")
        t1.setFrameOrigin(NSPoint(x: (W - t1.frame.width) / 2, y: 16 + 100 + 10))
        cover.addSubview(t1)
        let t2 = wLabel(sub, size: 11, weight: .regular, color: theme.tx2)
        t2.setFrameOrigin(NSPoint(x: (W - t2.frame.width) / 2, y: 16 + 100 + 10 + 21 + 2))
        cover.addSubview(t2)

        // 主按钮
        let btnStyle: WButton.Style = state == "live" ? .end : (state == "busy" ? .ghost : .primary)
        let btnTitle = state == "live" ? "结束语音" : (state == "busy" ? "取消连接" : "启动语音")
        let btn = WButton(btnTitle, style: btnStyle, w: W - 32, h: 28, fontSize: 13, radius: 8, theme: theme)
        btn.setFrameOrigin(NSPoint(x: 16, y: coverH - 13 - 28))
        btn.onClick = { [weak self] in
            guard let app = self?.app else { return }
            if app.voiceState == "busy" { app.cancelConnect() } else { app.toggleVoice() }
            self?.refresh()
        }
        cover.addSubview(btn)

        // ---- 菜单区 ----
        var y = coverH + 5
        let flyoutKinds = ["skin", "theme", "menubar"]
        for (i, r) in rows.enumerated() {
            if i == 4 || i == rows.count - 1 {   // 方案 A：个性化|帮助 与 帮助|退出 两条发丝分隔线
                let sep = NSView(frame: NSRect(x: 12, y: y + 4, width: W - 24, height: 1))
                sep.wantsLayer = true
                let sg = CAGradientLayer()
                sg.frame = sep.bounds
                sg.colors = [theme.sep.withAlphaComponent(0).cgColor, theme.sep.cgColor,
                             theme.sep.cgColor, theme.sep.withAlphaComponent(0).cgColor]
                sg.locations = [0, 0.18, 0.82, 1]
                sg.startPoint = CGPoint(x: 0, y: 0.5); sg.endPoint = CGPoint(x: 1, y: 0.5)
                sep.layer?.addSublayer(sg)
                root.addSubview(sep)
                y += 9
            }
            let row = WMenuRow(w: W, title: r.0, checked: r.1, chevron: r.2, theme: theme)
            row.setFrameOrigin(NSPoint(x: 0, y: y))
            row.onClick = r.3
            if i < flyoutKinds.count {
                // 悬停前三行自动飞出对应子菜单（原生菜单交互）
                let kind = flyoutKinds[i]
                row.onHover = { [weak self] inside in self?.flyoutRowHover(kind, inside) }
            } else {
                row.onHover = { [weak self] inside in if inside { self?.closeFlyout() } }
            }
            root.addSubview(row)
            y += 22
        }
        return root
    }

    // 悬停联动：进入行 → 开对应子菜单；离开行/飞出面板 0.25s 后关（进入飞出面板则取消关闭）
    private func flyoutRowHover(_ kind: String, _ inside: Bool) {
        if inside {
            flyoutCloseWork?.cancel()
            if flyout == nil || flyoutKind != kind { openFlyout(kind) }
        } else {
            scheduleFlyoutClose()
        }
    }

    private func scheduleFlyoutClose() {
        flyoutCloseWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.closeFlyout() }
        flyoutCloseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    // ---- 飞出子菜单（skin 球体样式 / theme 外观）----
    private func toggleFlyout(_ kind: String) {
        if flyout != nil && flyoutKind == kind { closeFlyout(); return }
        openFlyout(kind)
    }

    private func openFlyout(_ kind: String) {
        closeFlyout()
        guard let p = panel, let app else { return }
        flyoutKind = kind
        let theme = WTheme.current
        struct Item { let title: String; let checked: Bool; let dot: UInt32? ; let action: () -> Void }
        var items: [Item] = []
        if kind == "skin" {
            let dots: [UInt32] = [0x7FB2E8, 0x4E5FD0, 0x3FA7F5, 0x5A8CDC, 0x6A5AE0]
            let cur = app.orbView.currentSkin().id
            for (i, s) in SKINS.enumerated() {
                items.append(Item(title: s.title, checked: s.id == cur, dot: dots[i], action: { [weak self] in
                    app.orbView.applySkin(s)
                    self?.closeFlyout()
                    self?.refresh()
                }))
            }
        } else if kind == "theme" {
            let cur = UserDefaults.standard.string(forKey: "wispTheme") ?? "system"
            for (t, v) in [("跟随系统", "system"), ("深色", "dark"), ("浅色", "light")] {
                items.append(Item(title: t, checked: cur == v, dot: nil, action: { [weak self] in
                    self?.closeFlyout()
                    app.setTheme(v)
                }))
            }
        } else {   // menubar：显示 / 隐藏
            let hidden = UserDefaults.standard.bool(forKey: "hideMenuBar")
            for (t, v) in [("显示", true), ("隐藏", false)] {
                items.append(Item(title: t, checked: hidden != v, dot: nil, action: { [weak self] in
                    self?.closeFlyout()
                    app.setMenuBarVisible(v)
                }))
            }
        }
        let W: CGFloat = 180
        let H = CGFloat(8 + items.count * 22 + 8)
        let root = panelBackdrop(w: W, h: H, radius: 10, theme: theme)
        var y: CGFloat = 8
        for it in items {
            let row = WMenuRow(w: W, title: "", checked: it.checked, chevron: false, theme: theme)
            row.setFrameOrigin(NSPoint(x: 0, y: y))
            var tx: CGFloat = 30
            if let dc = it.dot {
                let dot = NSView(frame: NSRect(x: 30, y: 5, width: 12, height: 12))
                dot.wantsLayer = true
                let dg = CAGradientLayer()
                dg.type = .radial
                dg.frame = dot.bounds
                dg.cornerRadius = 6
                dg.startPoint = CGPoint(x: 0.40, y: 0.65); dg.endPoint = CGPoint(x: 1.0, y: 1.25)
                dg.colors = [NSColor.white.cgColor, NSColor(hex: dc).cgColor]
                dot.layer?.addSublayer(dg)
                row.addSubview(dot)
                tx = 48
            }
            let name = wLabel(it.title, size: 13, weight: .regular, color: theme.tx1)
            name.setFrameOrigin(NSPoint(x: tx, y: (22 - name.frame.height) / 2))
            row.addSubview(name)
            row.onClick = it.action
            root.addSubview(row)
            y += 22
        }
        // 悬停在飞出面板内 → 取消延迟关闭；移出 → 计划关闭
        root.onHover = { [weak self] inside in
            if inside { self?.flyoutCloseWork?.cancel() } else { self?.scheduleFlyoutClose() }
        }
        let f = NSPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        f.isOpaque = false; f.backgroundColor = .clear; f.hasShadow = true
        f.level = .popUpMenu
        f.contentView = root
        // 右侧放不下则放左侧；顶边与所属行对齐（上浮 4pt，同设计稿 fly top:-8px@2x）
        let scr = NSScreen.main?.visibleFrame ?? .zero
        let rightX = p.frame.maxX + 3
        let x = rightX + W > scr.maxX ? p.frame.minX - W - 3 : rightX
        let kindIdx = CGFloat(["skin", "theme", "menubar"].firstIndex(of: kind) ?? 0)
        let rowY = Self.styleRowY + 22 * kindIdx
        let rowTopScreen = p.frame.maxY - rowY
        f.setFrameOrigin(NSPoint(x: x, y: rowTopScreen + 4 - H))
        f.orderFrontRegardless()
        flyout = f
    }

    private func closeFlyout() {
        flyoutCloseWork?.cancel()
        flyout?.orderOut(nil)
        flyout = nil
        flyoutKind = nil
    }
}

// MARK: - 通用：设计稿风格窗口（透明标题栏 + 渐变底 + chrome 条）

func makeDesignWindow(title: String, w: CGFloat, h: CGFloat, theme: WTheme) -> (NSWindow, VFlip) {
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                       styleMask: [.titled, .closable, .fullSizeContentView],
                       backing: .buffered, defer: false)
    win.title = title
    win.titlebarAppearsTransparent = true
    win.isReleasedWhenClosed = false
    win.standardWindowButton(.miniaturizeButton)?.isHidden = true
    win.standardWindowButton(.zoomButton)?.isHidden = true
    let root = VFlip(frame: NSRect(x: 0, y: 0, width: w, height: h))
    root.wantsLayer = true
    let g = CAGradientLayer()
    g.frame = root.bounds
    g.colors = [theme.panel1.cgColor, theme.panel0.cgColor]
    g.startPoint = CGPoint(x: 0.5, y: 1); g.endPoint = CGPoint(x: 0.5, y: 0)
    root.layer?.addSublayer(g)
    // chrome 标题条 28pt + 发丝线
    let chrome = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 28))
    chrome.wantsLayer = true
    chrome.layer?.backgroundColor = theme.chrome.cgColor
    root.addSubview(chrome)
    let hair = NSView(frame: NSRect(x: 0, y: 28, width: w, height: 1))
    hair.wantsLayer = true
    hair.layer?.backgroundColor = theme.sep.cgColor
    root.addSubview(hair)
    win.contentView = root
    return (win, root)
}

/// 玻璃组容器
func glassGroup(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat, theme: WTheme) -> VFlip {
    let v = VFlip(frame: NSRect(x: x, y: y, width: w, height: h))
    v.wantsLayer = true
    v.layer?.backgroundColor = theme.glass.cgColor
    v.layer?.cornerRadius = radius
    v.layer?.borderWidth = 1
    v.layer?.borderColor = theme.stroke.cgColor
    return v
}

// MARK: - 三步安装引导窗（redesign）

final class OnboardUI {
    weak var app: AppDelegate?
    private var window: NSWindow?

    init(app: AppDelegate) { self.app = app }
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        rebuild()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard let w = window, w.isVisible else { return }
        let f = w.frame
        rebuild()
        window?.setFrame(f, display: true)
    }

    func closeWindow() { window?.orderOut(nil) }

    private func rebuild() {
        let theme = WTheme.current
        let W: CGFloat = 480, H: CGFloat = 322
        if window == nil {
            let (win, _) = makeDesignWindow(title: "Wisp 安装引导", w: W, h: H, theme: theme)
            window = win
        }
        let (_, root) = rebuildRoot(w: W, h: H, theme: theme)
        window?.contentView = root
    }

    private func rebuildRoot(w W: CGFloat, h H: CGFloat, theme: WTheme) -> (NSWindow, VFlip) {
        let win = window!
        let root = VFlip(frame: NSRect(x: 0, y: 0, width: W, height: H))
        root.wantsLayer = true
        let g = CAGradientLayer()
        g.frame = root.bounds
        g.colors = [theme.panel1.cgColor, theme.panel0.cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 1); g.endPoint = CGPoint(x: 0.5, y: 0)
        root.layer?.addSublayer(g)
        let chrome = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 28))
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = theme.chrome.cgColor
        root.addSubview(chrome)
        let hair = NSView(frame: NSRect(x: 0, y: 28, width: W, height: 1))
        hair.wantsLayer = true
        hair.layer?.backgroundColor = theme.sep.cgColor
        root.addSubview(hair)

        let ext = app?.extensionSeen ?? false
        let tab = ["idle", "live"].contains(app?.lastPageState ?? "")
        let all = ext && tab
        let pad: CGFloat = 16
        var y: CGFloat = 28 + 15

        // 头部：小球 + 标题
        let orb = GlassOrbView(diameter: 24)
        orb.setFrameOrigin(NSPoint(x: pad, y: y + 4))
        root.addSubview(orb)
        let h3 = wLabel(all ? "一切就绪" : "三步完成设置", size: 17, weight: .bold, color: theme.tx1)
        h3.setFrameOrigin(NSPoint(x: pad + 24 + 9, y: y))
        root.addSubview(h3)
        let hp = wLabel(all ? "Wisp 已连接你的 ChatGPT 语音" : "让 Wisp 连接你的 ChatGPT 语音",
                        size: 11, weight: .regular, color: theme.tx2)
        hp.setFrameOrigin(NSPoint(x: pad + 24 + 9, y: y + 22))
        root.addSubview(hp)
        y += 40 + 12

        // 步骤组
        let rowH: CGFloat = 44
        let group = glassGroup(x: pad, y: y, w: W - pad * 2, h: rowH * 3, radius: 10, theme: theme)
        root.addSubview(group)
        let steps: [(Bool, Bool, String, String, String?, (() -> Void)?)] = [
            (true, true, "安装 Wisp App", "已安装 · 版本 0.13", nil, nil),
            (ext, false, "安装 Chrome 扩展", ext ? "扩展已就绪" : "用于发现并接管 ChatGPT 标签页",
             ext ? nil : "打开扩展商店", { [weak self] in self?.app?.openStore() }),
            (tab, false, "连接 ChatGPT", tab ? "已连接 · 标签页常驻中" : "登录并让一个 ChatGPT 标签页保持打开",
             tab ? nil : "打开并固定 ChatGPT", { [weak self] in self?.app?.setupTab() }),
        ]
        for (i, st) in steps.enumerated() {
            let (done, dim, title, sub, btnTitle, act) = st
            let ry = CGFloat(i) * rowH
            if i > 0 {
                let s = NSView(frame: NSRect(x: 0, y: ry, width: group.frame.width, height: 1))
                s.wantsLayer = true; s.layer?.backgroundColor = theme.sep.cgColor
                group.addSubview(s)
            }
            // 状态圆 22pt
            let ic = NSView(frame: NSRect(x: 12, y: ry + 11, width: 22, height: 22))
            ic.wantsLayer = true
            ic.layer?.cornerRadius = 11
            if done {
                ic.layer?.backgroundColor = theme.ok.cgColor
                if !dim {  // 打勾光晕（仪式感）
                    ic.layer?.shadowColor = theme.ok.cgColor
                    ic.layer?.shadowOpacity = 0.45
                    ic.layer?.shadowRadius = 9
                    ic.layer?.shadowOffset = .zero
                }
                let ck = wLabel("✓", size: 12, weight: .bold, color: .white)
                ck.setFrameOrigin(NSPoint(x: (22 - ck.frame.width) / 2, y: (22 - ck.frame.height) / 2))
                ic.addSubview(ck)
            } else {
                ic.layer?.backgroundColor = theme.btnSec.cgColor
                ic.layer?.borderWidth = 1
                ic.layer?.borderColor = theme.stroke.cgColor
                let n = wLabel("\(i + 1)", size: 12, weight: .semibold, color: theme.tx2)
                n.setFrameOrigin(NSPoint(x: (22 - n.frame.width) / 2, y: (22 - n.frame.height) / 2))
                ic.addSubview(n)
            }
            group.addSubview(ic)
            let tl = wLabel(title, size: 13, weight: .semibold, color: theme.tx1)
            tl.setFrameOrigin(NSPoint(x: 44, y: ry + 7))
            group.addSubview(tl)
            let sl = wLabel(sub, size: 11, weight: .regular, color: theme.tx2)
            sl.setFrameOrigin(NSPoint(x: 44, y: ry + 24))
            group.addSubview(sl)
            if dim { ic.alphaValue = 0.45; tl.alphaValue = 0.45; sl.alphaValue = 0.45 }
            if let bt = btnTitle, let act {
                let font: CGFloat = 11
                let bw = wLabel(bt, size: font, weight: .medium, color: .white).frame.width + 22
                let style: WButton.Style = (i == firstPendingIndex(ext: ext, tab: tab)) ? .primary : .secondary
                let b = WButton(bt, style: style, w: bw, h: 22, fontSize: font, radius: 6, theme: theme)
                b.setFrameOrigin(NSPoint(x: group.frame.width - 12 - bw, y: ry + 11))
                b.onClick = act
                group.addSubview(b)
            }
        }
        y += rowH * 3 + 13

        // 底部：提示 + 开始使用
        let hint = all ? "按 ⌥⌘V 可随时唤起语音"
                       : (ext ? "还差一步：连接 ChatGPT" : "完成全部三步后，点击悬浮球即可通话")
        let hl = wLabel(hint, size: 11, weight: .regular, color: theme.tx3)
        hl.setFrameOrigin(NSPoint(x: pad, y: y + 8))
        root.addSubview(hl)
        let done = WButton("开始使用", style: all ? .primary : .ghost, w: 150, h: 28, fontSize: 13, radius: 8, theme: theme)
        done.setFrameOrigin(NSPoint(x: W - pad - 150, y: y))
        done.onClick = { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            self?.closeWindow()
        }
        root.addSubview(done)
        win.contentView = root
        return (win, root)
    }

    private func firstPendingIndex(ext: Bool, tab: Bool) -> Int {
        if !ext { return 1 }
        if !tab { return 2 }
        return -1
    }
}

// MARK: - 诊断结果弹窗（redesign）

final class DiagUI {
    weak var app: AppDelegate?
    private var window: NSWindow?

    init(app: AppDelegate) { self.app = app }

    /// report: nil=无回包(chrome 区分) / none / unready / idle / live
    func show(chrome: Bool, report: String?) {
        let theme = WTheme.current
        let W: CGFloat = 380

        // 头部文案 + 三行状态 + 修复动作
        struct Row { let name: String; let word: String; let kind: String } // kind: ok/err/warn/off
        var emblem = "✓", emblemKind = "ok", title = "一切正常", sub = "三项检查全部通过，可以开始语音对话。"
        var rows = [Row(name: "Wisp App", word: "正常", kind: "ok"),
                    Row(name: "Chrome 扩展", word: "已安装", kind: "ok"),
                    Row(name: "ChatGPT 标签页", word: "已连接", kind: "ok")]
        var fixTitle: String? = nil
        var fix: (() -> Void)? = nil
        switch report {
        case nil where !chrome:
            emblem = "✕"; emblemKind = "err"
            title = "Chrome 没有在运行"; sub = "Wisp 通过 Chrome 里的 ChatGPT 网页工作。"
            rows[1] = Row(name: "Chrome 扩展", word: "Chrome 未运行", kind: "err")
            rows[2] = Row(name: "ChatGPT 标签页", word: "等待上一步", kind: "off")
            fixTitle = "打开 Chrome"
            fix = { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Google Chrome.app")) }
        case nil:
            emblem = "✕"; emblemKind = "err"
            title = "Chrome 扩展未安装"; sub = "卡在第 ② 步：需要先安装 Wisp 浏览器扩展。"
            rows[1] = Row(name: "Chrome 扩展", word: "未安装", kind: "err")
            rows[2] = Row(name: "ChatGPT 标签页", word: "等待上一步", kind: "off")
            fixTitle = "打开扩展商店"
            fix = { [weak self] in self?.app?.openStore() }
        case "none":
            emblem = "✕"; emblemKind = "err"
            title = "没有找到 ChatGPT 标签页"; sub = "扩展已就绪，但浏览器里缺少常驻的 ChatGPT 页面。"
            rows[2] = Row(name: "ChatGPT 标签页", word: "未找到", kind: "err")
            fixTitle = "帮我打开并固定"
            fix = { [weak self] in self?.app?.setupTab() }
        case "unready":
            emblem = "!"; emblemKind = "warn"
            title = "ChatGPT 未登录"; sub = "标签页存在，但还没有登录，或页面未加载完成。"
            rows[2] = Row(name: "ChatGPT 标签页", word: "未登录", kind: "warn")
            fixTitle = "前往登录"
            fix = { [weak self] in self?.app?.setupTab() }
        default: break
        }

        let rowH: CGFloat = 32
        let H: CGFloat = 28 + 14 + 40 + 13 + rowH * 3 + 14 + 26 + 15
        if window == nil {
            let (win, _) = makeDesignWindow(title: "Wisp 诊断", w: W, h: H, theme: theme)
            window = win
        }
        let win = window!
        let root = VFlip(frame: NSRect(x: 0, y: 0, width: W, height: H))
        root.wantsLayer = true
        let g = CAGradientLayer()
        g.frame = root.bounds
        g.colors = [theme.panel1.cgColor, theme.panel0.cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 1); g.endPoint = CGPoint(x: 0.5, y: 0)
        root.layer?.addSublayer(g)
        let chrome2 = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 28))
        chrome2.wantsLayer = true
        chrome2.layer?.backgroundColor = theme.chrome.cgColor
        root.addSubview(chrome2)
        let hair = NSView(frame: NSRect(x: 0, y: 28, width: W, height: 1))
        hair.wantsLayer = true
        hair.layer?.backgroundColor = theme.sep.cgColor
        root.addSubview(hair)

        let pad: CGFloat = 20
        var y: CGFloat = 28 + 14

        // 头部：徽标 + 标题
        let colorOf: (String) -> NSColor = { k in
            k == "ok" ? theme.ok : (k == "err" ? theme.err : (k == "warn" ? theme.warn : theme.btnSec))
        }
        let em = NSView(frame: NSRect(x: pad, y: y + 4, width: 28, height: 28))
        em.wantsLayer = true
        em.layer?.cornerRadius = 14
        em.layer?.backgroundColor = colorOf(emblemKind).cgColor
        em.layer?.shadowColor = colorOf(emblemKind).cgColor
        em.layer?.shadowOpacity = 0.40; em.layer?.shadowRadius = 12; em.layer?.shadowOffset = .zero
        let el = wLabel(emblem, size: 14, weight: .bold, color: .white)
        el.setFrameOrigin(NSPoint(x: (28 - el.frame.width) / 2, y: (28 - el.frame.height) / 2))
        em.addSubview(el)
        root.addSubview(em)
        let tl = wLabel(title, size: 15, weight: .semibold, color: theme.tx1)
        tl.setFrameOrigin(NSPoint(x: pad + 28 + 10, y: y))
        root.addSubview(tl)
        let sl = wLabel(sub, size: 11, weight: .regular, color: theme.tx2)
        sl.setFrameOrigin(NSPoint(x: pad + 28 + 10, y: y + 22))
        root.addSubview(sl)
        y += 40 + 13

        // 三行检查
        let group = glassGroup(x: pad, y: y, w: W - pad * 2, h: rowH * 3, radius: 8, theme: theme)
        root.addSubview(group)
        let nums = ["①", "②", "③"]
        for (i, r) in rows.enumerated() {
            let ry = CGFloat(i) * rowH
            if i > 0 {
                let s = NSView(frame: NSRect(x: 0, y: ry, width: group.frame.width, height: 1))
                s.wantsLayer = true; s.layer?.backgroundColor = theme.sep.cgColor
                group.addSubview(s)
            }
            let n = wLabel(nums[i], size: 11, weight: .regular, color: theme.tx3)
            n.setFrameOrigin(NSPoint(x: 11, y: (rowH - n.frame.height) / 2 + ry))
            group.addSubview(n)
            let nm = wLabel(r.name, size: 13, weight: .regular, color: theme.tx1)
            nm.setFrameOrigin(NSPoint(x: 32, y: (rowH - nm.frame.height) / 2 + ry))
            group.addSubview(nm)
            // 状态点 16pt + 状态词
            let dotch = r.kind == "ok" ? "✓" : (r.kind == "err" ? "✕" : (r.kind == "warn" ? "!" : "–"))
            let dot = NSView(frame: NSRect(x: group.frame.width - 11 - 16, y: (rowH - 16) / 2 + ry, width: 16, height: 16))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 8
            dot.layer?.backgroundColor = colorOf(r.kind).cgColor
            if r.kind == "off" {
                dot.layer?.borderWidth = 1
                dot.layer?.borderColor = theme.stroke.cgColor
            }
            let dl = wLabel(dotch, size: 9, weight: .bold, color: r.kind == "off" ? theme.tx3 : .white)
            dl.setFrameOrigin(NSPoint(x: (16 - dl.frame.width) / 2, y: (16 - dl.frame.height) / 2))
            dot.addSubview(dl)
            group.addSubview(dot)
            let wd = wLabel(r.word, size: 11, weight: .regular, color: theme.tx2)
            wd.setFrameOrigin(NSPoint(x: group.frame.width - 11 - 16 - 6 - wd.frame.width,
                                      y: (rowH - wd.frame.height) / 2 + ry))
            group.addSubview(wd)
            if r.kind == "off" { [n, nm, wd].forEach { $0.alphaValue = 0.42 }; dot.alphaValue = 0.42 }
        }
        y += rowH * 3 + 14

        // 按钮：知道了 + 修复主按钮，右对齐
        var bx = W - pad
        if let ft = fixTitle {
            let bw = wLabel(ft, size: 12, weight: .medium, color: .white).frame.width + 28
            let b = WButton(ft, style: .primary, w: bw, h: 26, fontSize: 12, radius: 7, theme: theme)
            bx -= bw
            b.setFrameOrigin(NSPoint(x: bx, y: y))
            b.onClick = { [weak self] in self?.window?.orderOut(nil); fix?() }
            root.addSubview(b)
            bx -= 8
        }
        let okW = wLabel("知道了", size: 12, weight: .medium, color: .white).frame.width + 28
        let okB = WButton("知道了", style: .ghost, w: okW, h: 26, fontSize: 12, radius: 7, theme: theme)
        bx -= okW
        okB.setFrameOrigin(NSPoint(x: bx, y: y))
        okB.onClick = { [weak self] in self?.window?.orderOut(nil) }
        root.addSubview(okB)

        var f = win.frame
        f.size = NSSize(width: W, height: H)
        win.setFrame(f, display: true)
        win.contentView = root
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
