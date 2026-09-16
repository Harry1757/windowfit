import AppKit
import ApplicationServices
import Carbon

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func frameOf(_ window: AXUIElement) -> CGRect? {
    guard let p = attribute(window, kAXPositionAttribute), let s = attribute(window, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
@discardableResult func setFrame(_ window: AXUIElement, _ rect: CGRect) -> Bool {
    // Enhanced accessibility can animate Chrome's frame updates. Sequential
    // size/position requests then race with that animation despite returning success.
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    let app = AXUIElementCreateApplication(pid)
    let enhanced = (attribute(app, "AXEnhancedUserInterface") as? Bool) == true
    let disabled = enhanced && AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) == .success
    defer {
        if disabled { _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }
    var point = rect.origin, size = rect.size
    guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }
    // Size twice: some applications constrain size against the old display before moving.
    _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
    let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
    _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
    return moved == .success && resized == .success
}
func axRect(_ cocoa: CGRect) -> CGRect {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: cocoa.minX, y: top - cocoa.maxY, width: cocoa.width, height: cocoa.height)
}
func cocoaRect(_ ax: CGRect) -> CGRect { axRect(ax) }
func screenFor(_ rect: CGRect) -> NSScreen? {
    NSScreen.screens.max { a, b in
        let ar = axRect(a.frame).intersection(rect), br = axRect(b.frame).intersection(rect)
        return (ar.isNull ? 0 : ar.width * ar.height) < (br.isNull ? 0 : br.width * br.height)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var hotKeys: [EventHotKeyRef] = []
    var hotKeyFailures: [String] = []
    var monitor: Any?
    var saved: [(AXUIElement, CGRect)] = []
    var drag: (window: AXUIElement, original: CGRect)?
    var pending: (Layout, NSScreen)?
    var preview: NSPanel!
    var fixtureWindow: NSWindow?
    var fixtureProcess: Process?
    var verificationTimer: Timer?
    var verified = false
    let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var dragEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "edgeSnap") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "edgeSnap") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--fixture") {
            NSApp.setActivationPolicy(.regular)
            fixtureWindow = NSWindow(contentRect: NSRect(x: 180, y: 200, width: 560, height: 360), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            fixtureWindow?.title = "창맞춤 — 검증용 임시 창"
            fixtureWindow?.minSize = NSSize(width: 100, height: 100)
            let label = NSTextField(wrappingLabelWithString: "창 배치를 확인하는 임시 창입니다.\n검증이 끝나면 자동으로 닫힙니다.")
            label.frame = NSRect(x: 28, y: 160, width: 460, height: 70)
            label.font = .systemFont(ofSize: 20)
            fixtureWindow?.contentView?.addSubview(label)
            fixtureWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "창맞춤")
        status.button?.toolTip = "창맞춤 · Control + Option으로 창 정리"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let header = NSMenuItem(title: "창맞춤 · WindowFit", action: nil, keyEquivalent: ""); header.isEnabled = false
        menu.addItem(header); menu.addItem(permissionItem); menu.addItem(.separator())
        for layout in Layout.allCases {
            let item = NSMenuItem(title: "\(layout.title)    ⌃⌥\(layout.key)", action: #selector(arrange(_:)), keyEquivalent: "")
            item.target = self; item.tag = layout.rawValue; menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("가장자리로 끌어 놓기", #selector(toggleDrag(_:)), to: menu, tag: 100)
        addItem("손쉬운 사용 설정 열기…", #selector(openPermissions), to: menu)
        addItem("사용 방법…", #selector(showHelp), to: menu)
        addItem("임시 창으로 배치 점검", #selector(runVerification), to: menu)
        menu.addItem(.separator())
        addItem("종료", #selector(quit), to: menu)
        status.menu = menu
        preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isOpaque = false; preview.backgroundColor = .clear; preview.hasShadow = false
        preview.ignoresMouseEvents = true; preview.level = .floating
        preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        view.layer?.borderWidth = 3; view.layer?.cornerRadius = 12
        preview.contentView = view
        installHotKeys()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in self?.mouse(event) }
        if !AXIsProcessTrusted() { promptPermissions() }
        if CommandLine.arguments.contains("--verify-when-ready") || CommandLine.arguments.contains("--diagnose-chrome") {
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    if CommandLine.arguments.contains("--diagnose-chrome") { self.diagnoseChrome() } else { self.runVerification() }
                }
            }
        }
    }
    func addItem(_ title: String, _ selector: Selector, to menu: NSMenu, tag: Int = -1) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self; item.tag = tag; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        permissionItem.title = AXIsProcessTrusted() ? "● 창 제어 준비됨" : "○ 손쉬운 사용 권한 필요"
        permissionItem.isEnabled = false
        menu.item(withTag: 100)?.state = dragEnabled ? .on : .off
    }
    func installHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            if let layout = Layout(rawValue: Int(id.id) - 1) {
                delegate.trace("hotkey: \(layout.title), app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
                delegate.apply(layout)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        for layout in Layout.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x57464954, id: UInt32(layout.rawValue + 1))
            let result = RegisterEventHotKey(layout.keyCode, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotKeys.append(ref) } else { hotKeyFailures.append(layout.title) }
        }
        if !hotKeyFailures.isEmpty { alert("단축키 충돌", "다른 앱이 사용 중인 단축키: \(hotKeyFailures.joined(separator: ", ")). 메뉴에서는 배치할 수 있습니다.") }
    }
    func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return elementAttribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
    }
    @objc func arrange(_ item: NSMenuItem) { if let layout = Layout(rawValue: item.tag) { apply(layout) } }
    func apply(_ layout: Layout, window: AXUIElement? = nil, screen: NSScreen? = nil, original: CGRect? = nil) {
        guard AXIsProcessTrusted() else { promptPermissions(); return }
        guard let window = window ?? focusedWindow(), let current = frameOf(window) else { trace("missing focused window or frame"); NSSound.beep(); return }
        if (attribute(window, "AXFullScreen") as? Bool) == true { NSSound.beep(); return }
        if layout == .restore {
            if let index = saved.firstIndex(where: { CFEqual($0.0, window) }) {
                if setFrame(window, saved[index].1) { saved.remove(at: index) } else { NSSound.beep() }
            } else { NSSound.beep() }
            return
        }
        guard let display = screen ?? screenFor(current) else { return }
        if !saved.contains(where: { CFEqual($0.0, window) }) {
            // Retain at most 100 window handles, so closed applications cannot accumulate forever.
            if saved.count >= 100 { saved.removeFirst() }
            saved.append((window, original ?? current))
        }
        let target = layout.rect(in: axRect(display.visibleFrame), current: current)
        let success = setFrame(window, target)
        trace("apply \(layout.title): before=\(current) target=\(target) AXsuccess=\(success)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in guard let self else { return }; let actual = frameOf(window); self.trace("after: \(String(describing: actual)); matched=\(actual.map { abs($0.minX-target.minX)<3 && abs($0.minY-target.minY)<3 && abs($0.width-target.width)<3 && abs($0.height-target.height)<3 } ?? false)") }
        if !success { NSSound.beep() }
    }
    func mouse(_ event: NSEvent) {
        guard dragEnabled, AXIsProcessTrusted() else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
        switch event.type {
        case .leftMouseDown:
            drag = nil; pending = nil; preview.orderOut(nil)
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success, let hit else { return }
            let window = (attribute(hit, kAXRoleAttribute) as? String) == kAXWindowRole ? hit : elementAttribute(hit, kAXWindowAttribute)
            if let window, let original = frameOf(window) {
                drag = (window, original)
                trace("drag captured: \(original)")
            } else { trace("drag window lookup failed") }
        case .leftMouseDragged:
            guard let drag, let current = frameOf(drag.window) else { return }
            // A real window move must occur; dragging text or resizing must not trigger a snap.
            guard hypot(current.minX - drag.original.minX, current.minY - drag.original.minY) > 5,
                  abs(current.width - drag.original.width) < 4, abs(current.height - drag.original.height) < 4,
                  !event.modifierFlags.contains(.option),
                  let display = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
                  let layout = Layout.edge(at: point, in: axRect(display.frame)) else {
                pending = nil; preview.orderOut(nil); return
            }
            pending = (layout, display)
            preview.setFrame(cocoaRect(layout.rect(in: axRect(display.visibleFrame), current: current)).insetBy(dx: 5, dy: 5), display: true)
            preview.orderFrontRegardless()
        case .leftMouseUp:
            if drag != nil { trace("drag released: pending=\(String(describing: pending?.0.title))") }
            preview.orderOut(nil)
            if let drag, let (layout, display) = pending, !event.modifierFlags.contains(.option),
               Layout.edge(at: point, in: axRect(display.frame)) == layout {
                // Wait until the target app finishes its own mouse-up handling.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.apply(layout, window: drag.window, screen: display, original: drag.original) }
            }
            drag = nil; pending = nil
        default: break
        }
    }
    @objc func toggleDrag(_ item: NSMenuItem) { dragEnabled.toggle(); item.state = dragEnabled ? .on : .off; pending = nil; drag = nil; preview.orderOut(nil) }
    func promptPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc func openPermissions() {
        promptPermissions()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func showHelp() {
        alert("창맞춤 사용 방법", "창을 선택한 뒤 Control + Option + 방향키로 절반 배치합니다.\n\nU / I / J / K: 네 모서리\nReturn: 화면에 맞추기\nC: 가운데로\nDelete: 원래 크기로\n\n창 제목 막대를 화면 가장자리로 끌고 놓아도 됩니다. Option을 누른 채 놓으면 취소합니다.\n\nmacOS 기본 창 타일링과 겹치면 시스템 설정 → 데스크탑 및 Dock에서 가장자리 창 타일링을 끄세요.\n앱의 최소 창 크기나 전체 화면 모드에서는 배치가 제한될 수 있습니다.")
    }
    func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message; alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc func runVerification() {
        guard AXIsProcessTrusted() else { promptPermissions(); return }
        guard fixtureProcess == nil else { return }
        let process = Process(); process.executableURL = Bundle.main.executableURL; process.arguments = ["--fixture"]
        do { try process.run(); fixtureProcess = process } catch { alert("점검 실패", error.localizedDescription); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.verifyFixture(process, attempts: 0) }
    }
    func verifyFixture(_ process: Process, attempts: Int) {
        let app = AXUIElementCreateApplication(process.processIdentifier)
        guard let window = elementAttribute(app, kAXFocusedWindowAttribute), let original = frameOf(window), let display = screenFor(original) else {
            if attempts < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.verifyFixture(process, attempts: attempts + 1) }
            } else { finishVerification(process, result: ["passed": false, "error": "Test window unavailable"]) }
            return
        }
        verifyLayout(process, window: window, original: original, display: display, layouts: Layout.allCases, results: [])
    }
    func verifyLayout(_ process: Process, window: AXUIElement, original: CGRect, display: NSScreen, layouts: [Layout], results: [[String: Any]]) {
        guard let layout = layouts.first else {
            finishVerification(process, result: ["passed": results.allSatisfy { $0["passed"] as? Bool == true } && hotKeyFailures.isEmpty,
                                                 "layouts": results, "registeredHotKeys": hotKeys.count, "hotKeyFailures": hotKeyFailures,
                                                 "note": "Real separate-process AX window placement and restore. Physical key dispatch and mouse dragging require manual verification."])
            return
        }
        let current = frameOf(window) ?? original
        let expected = layout == .restore ? original : layout.rect(in: axRect(display.visibleFrame), current: current)
        apply(layout, window: window, screen: display)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self else { return }
            let actual = frameOf(window) ?? .zero
            let pass = abs(actual.minX - expected.minX) < 3 && abs(actual.minY - expected.minY) < 3 && abs(actual.width - expected.width) < 3 && abs(actual.height - expected.height) < 3
            let entry: [String: Any] = ["layout": layout.title, "passed": pass, "expected": NSStringFromRect(expected), "actual": NSStringFromRect(actual)]
            self.verifyLayout(process, window: window, original: original, display: display, layouts: Array(layouts.dropFirst()), results: results + [entry])
        }
    }
    func finishVerification(_ process: Process, result: [String: Any]) {
        if process.isRunning { process.terminate() }; fixtureProcess = nil
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("verification.json")
        do {
            var report = result; report["date"] = ISO8601DateFormatter().string(from: Date())
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            status.button?.toolTip = (result["passed"] as? Bool == true) ? "창맞춤 · 배치 점검 통과" : "창맞춤 · 점검 결과 확인 필요"
        } catch { alert("점검 결과 저장 실패", error.localizedDescription) }
    }
    func trace(_ text: String) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("diagnostic.log")
        let data = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n".data(using: .utf8)!
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) { defer { try? file.close() }; file.seekToEndOfFile(); file.write(data) }
    }
    func diagnoseChrome() {
        guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { trace("Chrome not running"); return }
        let app = AXUIElementCreateApplication(chrome.processIdentifier)
        trace("Chrome enhancedUI=\(String(describing: attribute(app, "AXEnhancedUserInterface")))")
        guard let window = elementAttribute(app, kAXFocusedWindowAttribute), let original = frameOf(window), let display = screenFor(original) else { trace("Chrome focused window unavailable"); return }
        trace("Chrome original=\(original) fullscreen=\(String(describing: attribute(window, "AXFullScreen")))")
        diagnoseNext(window, original: original, display: display, layouts: Layout.allCases.filter { $0 != .restore })
    }
    func diagnoseNext(_ window: AXUIElement, original: CGRect, display: NSScreen, layouts: [Layout]) {
        guard let layout = layouts.first else { setFrame(window, original); trace("Chrome diagnosis complete; restored original"); return }
        setFrame(window, original)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.apply(layout, window: window, screen: display)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.diagnoseNext(window, original: original, display: display, layouts: Array(layouts.dropFirst())) }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let process = fixtureProcess, process.isRunning { process.terminate() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
