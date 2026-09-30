import AppKit
import ApplicationServices

@MainActor
final class MacActivitySource: ActivitySource {
    private var continuation: AsyncStream<CaptureTrigger>.Continuation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var pollTask: Task<Void, Never>?
    private var pollingInterval: TimeInterval = 5
    private var lastExternalContext: ActiveWindowContext?

    func observe() -> AsyncStream<CaptureTrigger> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.installWorkspaceObservers()
            self.attachAccessibilityObserver()
            self.restartPoller()
            continuation.yield(.activated)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func currentContext() -> ActiveWindowContext? {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // The system-wide element is more reliable during focus transitions than
        // asking NSWorkspace's frontmost process for AXFocusedWindow directly.
        let system = AXUIElementCreateSystemWide()
        let systemApplication = Self.elementAttribute(system, kAXFocusedApplicationAttribute as CFString)
        let systemWindow = Self.elementAttribute(system, kAXFocusedWindowAttribute as CFString)

        var pid: pid_t = 0
        if let systemApplication { AXUIElementGetPid(systemApplication, &pid) }
        if pid == 0, let systemWindow { AXUIElementGetPid(systemWindow, &pid) }
        if pid == 0 { pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0 }

        guard pid != 0 else { return lastExternalContext }
        if pid == ownPID { return lastExternalContext }

        let application = NSRunningApplication(processIdentifier: pid)
        guard let bundleID = application?.bundleIdentifier else { return lastExternalContext }
        let appElement = systemApplication ?? AXUIElementCreateApplication(pid)

        let window = systemWindow
            ?? Self.elementAttribute(appElement, kAXFocusedWindowAttribute as CFString)
            ?? Self.firstWindow(appElement)
        let title = window.flatMap { Self.stringAttribute($0, kAXTitleAttribute as CFString) }
            ?? application?.localizedName
            ?? bundleID
        let context = ActiveWindowContext(
            pid: pid,
            bundleID: bundleID,
            appName: application?.localizedName ?? bundleID,
            windowTitle: title,
            // Falling back to the app element still permits useful traversal for
            // applications that don't vend a focused window.
            accessibilityWindow: window ?? appElement
        )
        lastExternalContext = context
        return context
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        guard pollingInterval != interval else { return }
        pollingInterval = interval
        restartPoller()
    }

    private func installWorkspaceObservers() {
        guard notificationTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.attachAccessibilityObserver()
                self?.continuation?.yield(.activated)
            }
        })
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.continuation?.yield(.sessionLocked)
            })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.continuation?.yield(.sessionUnlocked)
            })
        }
    }

    private func attachAccessibilityObserver() {
        detachAccessibilityObserver()
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, pointer in
            guard let pointer else { return }
            let source = Unmanaged<MacActivitySource>.fromOpaque(pointer).takeUnretainedValue()
            Task { @MainActor in source.continuation?.yield(.accessibilityChanged) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let notifications: [CFString] = [
            kAXFocusedWindowChangedNotification as CFString,
            kAXWindowCreatedNotification as CFString,
            kAXTitleChangedNotification as CFString,
            kAXValueChangedNotification as CFString,
            kAXSelectedTextChangedNotification as CFString,
            kAXLayoutChangedNotification as CFString
        ]
        for notification in notifications {
            AXObserverAddNotification(observer, app, notification, pointer)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        observedPID = pid
    }

    private func detachAccessibilityObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        observedPID = nil
    }

    private func restartPoller() {
        pollTask?.cancel()
        let interval = pollingInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.continuation?.yield(.poll)
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
        detachAccessibilityObserver()
        let center = NSWorkspace.shared.notificationCenter
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? String
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func firstWindow(_ application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first
    }
}
