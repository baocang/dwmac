import ApplicationServices
import Cocoa
import Foundation

/// Events emitted by the observer system. Always delivered on the main thread.
enum WindowEvent {
    case appeared(AXUIElement, pid_t, bundleID: String?)
    case destroyed(AXUIElement, pid_t)
    case movedOrResized(AXUIElement, pid_t)
    case minimized(AXUIElement, pid_t)
    case demined(AXUIElement, pid_t)
    case appQuit(pid_t)
    case focusedWindowChanged
}

/// Holds one AXObserver per running app and bridges its callbacks back into Swift.
final class WindowObserver {
    /// Called for every event. Set after init.
    var onEvent: ((WindowEvent) -> Void)?

    private var perApp: [pid_t: AXObserver] = [:]
    private var perAppBundleID: [pid_t: String] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    func start() {
        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter

        let launched = nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                       object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(to: app)
        }
        let terminated = nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                         object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.detach(pid: app.processIdentifier)
            self?.onEvent?(.appQuit(app.processIdentifier))
        }
        let activated = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?(.focusedWindowChanged)
        }
        workspaceTokens = [launched, terminated, activated]

        // Attach to currently running apps.
        for app in ws.runningApplications where app.activationPolicy == .regular {
            attach(to: app)
        }
    }

    func stop() {
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        for (_, obs) in perApp {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(obs),
                                  .defaultMode)
        }
        perApp.removeAll()
        perAppBundleID.removeAll()
    }

    /// Snapshot current windows of every running regular app — call once at boot.
    func enumerateAllExistingWindows(onWindow: (AXUIElement, pid_t, String?) -> Void) {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let appEl = AppAX.application(pid: pid)
            for win in AppAX.windows(of: appEl) {
                onWindow(win, pid, app.bundleIdentifier)
            }
        }
    }

    // MARK: - Private

    private func attach(to app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        if perApp[pid] != nil { return }

        var observer: AXObserver?
        let createStatus = AXObserverCreate(pid, axObserverCallback, &observer)
        guard createStatus == .success, let observer else {
            Log.debug("AXObserverCreate failed for pid=\(pid): \(createStatus.rawValue)")
            return
        }

        let appEl = AppAX.application(pid: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications: [CFString] = [
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
            kAXWindowMovedNotification as CFString,
            kAXWindowResizedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString
        ]
        for n in notifications {
            let s = AXObserverAddNotification(observer, appEl, n, refcon)
            if s != .success && s != .notificationAlreadyRegistered {
                Log.debug("AXObserverAddNotification(\(n)) pid=\(pid): \(s.rawValue)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           .defaultMode)

        perApp[pid] = observer
        perAppBundleID[pid] = app.bundleIdentifier ?? ""
        Log.debug("attached AXObserver to pid=\(pid) bundle=\(app.bundleIdentifier ?? "?")")
    }

    private func detach(pid: pid_t) {
        guard let observer = perApp.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                              AXObserverGetRunLoopSource(observer),
                              .defaultMode)
        perAppBundleID.removeValue(forKey: pid)
        Log.debug("detached AXObserver pid=\(pid)")
    }

    fileprivate func dispatch(element: AXUIElement, notification: CFString) {
        // Resolve pid of the owning app.
        var pidValue: pid_t = 0
        AXUIElementGetPid(element, &pidValue)
        let bundleID = perAppBundleID[pidValue]

        let n = notification as String
        switch n {
        case kAXWindowCreatedNotification:
            onEvent?(.appeared(element, pidValue, bundleID: bundleID))
        case kAXUIElementDestroyedNotification:
            onEvent?(.destroyed(element, pidValue))
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            onEvent?(.movedOrResized(element, pidValue))
        case kAXWindowMiniaturizedNotification:
            onEvent?(.minimized(element, pidValue))
        case kAXWindowDeminiaturizedNotification:
            onEvent?(.demined(element, pidValue))
        case kAXFocusedWindowChangedNotification:
            onEvent?(.focusedWindowChanged)
        default:
            break
        }
    }
}

/// C trampoline for AXObserver. refcon is the WindowObserver pointer.
private let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let me = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    me.dispatch(element: element, notification: notification)
}
