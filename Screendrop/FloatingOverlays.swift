import AppKit
import UniformTypeIdentifiers

class FloatingCardView: NSView {
    static let shadowPadding: CGFloat = 44
    private static let resizeBand: CGFloat = 14

    static func makePanel(contentRect: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect.insetBy(dx: -shadowPadding, dy: -shadowPadding),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    let contentLayer: CALayer
    let keepsAspectRatio: Bool
    var onFrameChange: (() -> Void)?

    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()

    init(contentLayer: CALayer, keepsAspectRatio: Bool, background: NSColor?, border: Bool, hasShadow: Bool = true) {
        self.contentLayer = contentLayer
        self.keepsAspectRatio = keepsAspectRatio
        super.init(frame: .zero)
        wantsLayer = true

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = hasShadow ? 0.4 : 0
        shadowLayer.shadowRadius = 22
        shadowLayer.shadowOffset = CGSize(width: 0, height: -12)

        clipLayer.masksToBounds = true
        clipLayer.backgroundColor = background?.cgColor
        if border {
            clipLayer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            clipLayer.borderWidth = 1
        }

        clipLayer.addSublayer(contentLayer)
        layer?.addSublayer(shadowLayer)
        layer?.addSublayer(clipLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var contentRect: CGRect {
        bounds.insetBy(dx: Self.shadowPadding, dy: Self.shadowPadding)
    }

    var screenContentRect: CGRect? {
        window?.frame.insetBy(dx: Self.shadowPadding, dy: Self.shadowPadding)
    }

    var cornerRadius: CGFloat { min(contentRect.width, contentRect.height) * 0.12 }
    var usesCircularCorners: Bool { false }

    func fittedSize(_ proposed: CGSize) -> CGSize {
        CGSize(width: min(max(proposed.width, 60), 1600).rounded(), height: min(max(proposed.height, 24), 1000).rounded())
    }

    func contentDidLayout() {}

    func setScreenContent(_ rect: CGRect) {
        window?.setFrame(rect.insetBy(dx: -Self.shadowPadding, dy: -Self.shadowPadding), display: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = contentRect
        let radius = cornerRadius
        clipLayer.frame = rect
        clipLayer.cornerRadius = radius
        clipLayer.cornerCurve = usesCircularCorners ? .circular : .continuous
        contentLayer.frame = clipLayer.bounds
        shadowLayer.frame = rect
        shadowLayer.shadowPath = CGPath(
            roundedRect: shadowLayer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil
        )
        CATransaction.commit()
        contentDidLayout()
    }

    private func shapePath(insetBy inset: CGFloat) -> CGPath {
        let rect = contentRect.insetBy(dx: inset, dy: inset)
        let radius = min(max(0, cornerRadius - inset), min(rect.width, rect.height) / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private enum Hit { case outside, move, resize(right: Bool, top: Bool) }

    private func hit(at point: CGPoint) -> Hit {
        guard shapePath(insetBy: 0).contains(point) else { return .outside }
        if shapePath(insetBy: Self.resizeBand).contains(point) { return .move }
        return .resize(right: point.x > contentRect.midX, top: point.y > contentRect.midY)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .resize(let right, let top):
            let position: NSCursor.FrameResizePosition = switch (right, top) {
            case (true, true): .topRight
            case (false, true): .topLeft
            case (true, false): .bottomRight
            case (false, false): .bottomLeft
            }
            NSCursor.frameResize(position: position, directions: .all).set()
        case .move, .outside:
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .outside:
            return
        case .move:
            window.performDrag(with: event)
        case .resize(let right, let top):
            trackResize(window: window, right: right, top: top)
            onFrameChange?()
        }
    }

    private func trackResize(window: NSWindow, right: Bool, top: Bool) {
        let start = window.frame.insetBy(dx: Self.shadowPadding, dy: Self.shadowPadding)
        let aspect = start.height / start.width
        let anchor = CGPoint(x: right ? start.minX : start.maxX, y: top ? start.minY : start.maxY)
        let mouseStart = NSEvent.mouseLocation
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), event.type != .leftMouseUp {
            let mouse = NSEvent.mouseLocation
            let alongX = (mouse.x - mouseStart.x) * (right ? 1 : -1)
            let alongY = (mouse.y - mouseStart.y) * (top ? 1 : -1)
            let proposed: CGSize
            if keepsAspectRatio {
                let growth = abs(alongX) > abs(alongY / aspect) ? alongX : alongY / aspect
                proposed = CGSize(width: start.width + growth, height: (start.width + growth) * aspect)
            } else {
                proposed = CGSize(width: start.width + alongX, height: start.height + alongY)
            }
            let size = fittedSize(proposed)
            setScreenContent(CGRect(
                x: right ? anchor.x : anchor.x - size.width,
                y: top ? anchor.y : anchor.y - size.height,
                width: size.width,
                height: size.height
            ))
        }
    }
}

// MARK: - Overlays

private final class ImageOverlayView: FloatingCardView {
    var onRemove: (() -> Void)?

    init(image: NSImage) {
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        super.init(contentLayer: layer, keepsAspectRatio: true, background: nil, border: false, hasShadow: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Remove") { [weak self] in self?.onRemove?() })
        return menu
    }
}

private final class TickerOverlayView: FloatingCardView {
    private static let speed: CGFloat = 70
    private static let gap: CGFloat = 80

    var onEdit: (() -> Void)?
    var onRemove: (() -> Void)?
    var text: String { didSet { needsLayout = true } }

    private let strip = CALayer()
    private var laidOut: (size: CGSize, text: String)?

    init(text: String) {
        self.text = text
        let container = CALayer()
        container.masksToBounds = true
        strip.anchorPoint = .zero
        container.addSublayer(strip)
        super.init(
            contentLayer: container,
            keepsAspectRatio: false,
            background: NSColor.black.withAlphaComponent(0.75),
            border: true
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func contentDidLayout() {
        let size = contentRect.size
        guard size.width > 0, size.height > 0, laidOut?.size != size || laidOut?.text != text else { return }
        laidOut = (size, text)

        let font = NSFont.monospacedSystemFont(ofSize: max(10, size.height * 0.48), weight: .semibold)
        let textSize = NSAttributedString(string: text, attributes: [.font: font]).size()
        let step = ceil(textSize.width) + Self.gap
        let copies = Int(ceil(size.width / step)) + 1
        let scale = window?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.sublayers?.forEach { $0.removeFromSuperlayer() }
        strip.removeAllAnimations()
        strip.frame = CGRect(x: 0, y: 0, width: step * CGFloat(copies), height: size.height)
        for index in 0..<copies {
            let textLayer = CATextLayer()
            textLayer.string = text
            textLayer.font = font
            textLayer.fontSize = font.pointSize
            textLayer.foregroundColor = NSColor.white.cgColor
            textLayer.contentsScale = scale
            textLayer.frame = CGRect(
                x: CGFloat(index) * step,
                y: ((size.height - textSize.height) / 2).rounded(),
                width: ceil(textSize.width),
                height: ceil(textSize.height)
            )
            strip.addSublayer(textLayer)
        }
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = -step
        animation.duration = step / Self.speed
        animation.repeatCount = .infinity
        strip.add(animation, forKey: "scroll")
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: "Edit Text…") { [weak self] in self?.onEdit?() })
        menu.addItem(ClosureMenuItem(title: "Remove") { [weak self] in self?.onRemove?() })
        return menu
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() { handler() }
}

final class FloatingOverlays {
    static let shared = FloatingOverlays()

    private struct Item: Codable {
        var id = UUID()
        var imageFile: String?
        var text: String?
        var frame: CGRect
    }

    private static let defaultsKey = "floatingOverlays"

    private var items: [Item] = []
    private var panels: [UUID: NSPanel] = [:]

    private init() {}

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screendrop/Overlays", isDirectory: true)
    }

    func restore() {
        guard panels.isEmpty,
              let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = saved.filter { $0.text != nil || $0.imageFile.map { FileManager.default.fileExists(atPath: Self.directory.appendingPathComponent($0).path) } == true }
        items.indices.forEach { items[$0].frame = Self.onScreen(items[$0].frame) }
        items.forEach(show)
    }

    func addImage() {
        NSApp.activate()
        let open = NSOpenPanel()
        open.allowedContentTypes = [.image]
        open.allowsMultipleSelection = false
        guard open.runModal() == .OK, let source = open.url, let image = NSImage(contentsOf: source) else { return }

        let fileName = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: Self.directory.appendingPathComponent(fileName))
        } catch {
            NSSound.beep()
            return
        }

        let width: CGFloat = 240
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1
        let size = CGSize(width: width, height: (width * aspect).rounded())
        add(Item(imageFile: fileName, frame: Self.centered(size)))
    }

    func addText() {
        guard let text = Self.promptText(initial: "") else { return }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let size = CGSize(width: min(640, visible.width - 80), height: 44)
        add(Item(text: text, frame: CGRect(x: visible.midX - size.width / 2, y: visible.minY + 40, width: size.width, height: size.height)))
    }

    private func add(_ item: Item) {
        items.append(item)
        show(item)
        save()
    }

    private func show(_ item: Item) {
        let view: FloatingCardView
        if let text = item.text {
            let ticker = TickerOverlayView(text: text)
            ticker.onEdit = { [weak self, weak ticker] in
                guard let ticker, let text = Self.promptText(initial: ticker.text) else { return }
                ticker.text = text
                self?.update(item.id) { $0.text = text }
            }
            ticker.onRemove = { [weak self] in self?.remove(item.id) }
            view = ticker
        } else if let file = item.imageFile, let image = NSImage(contentsOf: Self.directory.appendingPathComponent(file)) {
            let imageView = ImageOverlayView(image: image)
            imageView.onRemove = { [weak self] in self?.remove(item.id) }
            view = imageView
        } else {
            return
        }
        view.onFrameChange = { [weak self, weak view] in
            guard let frame = view?.screenContentRect else { return }
            self?.update(item.id) { $0.frame = frame }
        }

        let panel = FloatingCardView.makePanel(contentRect: item.frame)
        panel.sharingType = .readOnly
        panel.contentView = view
        panel.orderFrontRegardless()
        panels[item.id] = panel
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self, weak view] _ in
            MainActor.assumeIsolated {
                guard let frame = view?.screenContentRect else { return }
                self?.update(item.id) { $0.frame = frame }
            }
        }
    }

    func move(by offset: CGVector) {
        for panel in panels.values {
            panel.setFrameOrigin(CGPoint(x: panel.frame.minX + offset.dx, y: panel.frame.minY + offset.dy))
        }
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    private func remove(_ id: UUID) {
        panels.removeValue(forKey: id)?.orderOut(nil)
        if let index = items.firstIndex(where: { $0.id == id }) {
            if let file = items[index].imageFile {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file))
            }
            items.remove(at: index)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: Self.defaultsKey)
    }

    private static func centered(_ size: CGSize) -> CGRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func onScreen(_ frame: CGRect) -> CGRect {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return frame }
        return centered(frame.size)
    }

    private static func promptText(initial: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Running Text"
        alert.informativeText = "It scrolls in a bar you can drag and resize anywhere on screen."
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = initial
        field.placeholderString = "Support me on Saweria: saweria.co/yourname"
        alert.accessoryView = field
        alert.addButton(withTitle: initial.isEmpty ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
