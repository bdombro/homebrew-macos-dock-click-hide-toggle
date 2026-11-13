#!/usr/bin/env swift
import Cocoa
import ApplicationServices

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

let usage = "Usage: macos-dock-click-hide-toggle <start|--version|--help>"

guard CommandLine.arguments.count == 2 else { fail(usage) }
switch CommandLine.arguments[1] {
case "-h", "--help":
    print("""
    \(usage)

      start      Run in the foreground until Ctrl+C.
      --version  Print the current version.
      --help, -h Show this help.
    Click the frontmost app's Dock icon to hide it. Other Dock clicks,
    modified clicks, and drags retain their normal behavior.
    Requires Accessibility permission on each Mac.
    """)
    exit(0)
case "--version":
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
        fail("Version metadata is missing. Build the executable with scripts/build.ts.")
    }
    print(version)
    exit(0)
case "start":
    break
default:
    fail(usage)
}

final class DockClickHandler {
    var tap: CFMachPort?
    var candidate: NSRunningApplication?
    var pendingMouseDown: CGEvent?
    var lastAccessibilityError: AXError?

    func replayMouseDown(proxy: CGEventTapProxy) {
        if let pendingMouseDown {
            pendingMouseDown.tapPostEvent(proxy)
        }
        pendingMouseDown = nil
        candidate = nil
    }

    func report(_ error: AXError) {
        guard error != .success, error != .noValue,
              error != lastAccessibilityError else { return }
        lastAccessibilityError = error
        fputs("Cannot inspect the Dock (Accessibility error \(error.rawValue)). Check Accessibility permission.\n", stderr)
    }

    func applicationURL(at point: CGPoint) -> URL? {
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else { return nil }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var element: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(
            application, Float(point.x), Float(point.y), &element
        )
        guard hitError == .success, let element else {
            report(hitError)
            return nil
        }

        var subrole: CFTypeRef?
        let subroleError = AXUIElementCopyAttributeValue(
            element, kAXSubroleAttribute as CFString, &subrole
        )
        guard subroleError == .success else {
            if subroleError != .attributeUnsupported { report(subroleError) }
            return nil
        }
        guard subrole as? String == "AXApplicationDockItem" else { return nil }

        var value: CFTypeRef?
        let urlError = AXUIElementCopyAttributeValue(
            element, kAXURLAttribute as CFString, &value
        )
        guard urlError == .success else {
            report(urlError)
            return nil
        }
        guard let url = value as? URL, url.isFileURL else {
            fputs("The Dock application icon did not expose a file URL.\n", stderr)
            return nil
        }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            candidate = nil
            pendingMouseDown = nil
            fputs("Dock event tap was disabled; re-enabling it.\n", stderr)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return unchanged
        }
        if type == .leftMouseDragged {
            replayMouseDown(proxy: proxy)
            return unchanged
        }

        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard event.flags.intersection(modifiers).isEmpty,
              event.getIntegerValueField(.mouseEventClickState) == 1 else {
            replayMouseDown(proxy: proxy)
            return unchanged
        }

        if type == .leftMouseDown {
            candidate = nil
            pendingMouseDown = nil
            // Capture before the Dock can activate a different app.
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  !frontmost.isHidden,
                  let bundleURL = frontmost.bundleURL,
                  applicationURL(at: event.location) ==
                    bundleURL.resolvingSymlinksInPath().standardizedFileURL else {
                return unchanged
            }
            guard let copy = event.copy() else {
                fputs("Cannot buffer the Dock mouse-down event.\n", stderr)
                return unchanged
            }
            candidate = frontmost
            pendingMouseDown = copy
            return nil
        } else if type == .leftMouseUp {
            defer {
                candidate = nil
                pendingMouseDown = nil
            }
            guard let application = candidate,
                  !application.isTerminated,
                  let bundleURL = application.bundleURL,
                  applicationURL(at: event.location) ==
                    bundleURL.resolvingSymlinksInPath().standardizedFileURL else {
                replayMouseDown(proxy: proxy)
                return unchanged
            }
            let target = AXUIElementCreateApplication(application.processIdentifier)
            let hideError = AXUIElementSetAttributeValue(
                target, kAXHiddenAttribute as CFString, kCFBooleanTrue
            )
            guard hideError == .success else {
                fputs("Could not hide \(application.localizedName ?? "the application") (Accessibility error \(hideError.rawValue)).\n", stderr)
                replayMouseDown(proxy: proxy)
                return unchanged
            }
            // The Dock must see neither half, or it can activate the app or open its menu.
            return nil
        }
        return unchanged
    }
}

let handler = DockClickHandler()
func startMonitoring() {
    fputs("Accessibility approved; creating the Dock mouse event tap.\n", stderr)
    let events: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: events,
        callback: { proxy, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<DockClickHandler>.fromOpaque(context)
                .takeUnretainedValue().handle(proxy: proxy, type: type, event: event)
        },
        userInfo: Unmanaged.passUnretained(handler).toOpaque()
    ) else {
        fail("Cannot monitor Dock clicks. Check Accessibility access for your terminal or the installed executable.")
    }
    handler.tap = tap
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        fail("Cannot create the Dock event run-loop source.")
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    fputs("Dock click-to-hide is running (pid \(getpid())). Press Ctrl+C to stop.\n", stderr)
}

let application = NSApplication.shared
guard application.setActivationPolicy(.accessory) else {
    fail("Cannot initialize the background AppKit application.")
}
fputs("Starting Dock click-to-hide (pid \(getpid())).\n", stderr)
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
if AXIsProcessTrustedWithOptions(options as CFDictionary) {
    startMonitoring()
} else {
    fputs("Waiting for Accessibility approval. Allow this executable (or your terminal when running there) in System Settings > Privacy & Security > Accessibility / Device Control and Data Access. Press Ctrl+C to cancel.\n", stderr)
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        if AXIsProcessTrusted() {
            timer.invalidate()
            startMonitoring()
        }
    }
}
application.run()
