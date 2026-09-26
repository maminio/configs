import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Constants

private let windowsPollInterval: TimeInterval = 1.5
private let focusedStatePath = "/tmp/aerospace-hud-focused-workspace"

// macOS virtual keycodes.
private enum Key {
    static let tab: Int64 = 48
    static let one: Int64 = 18
    static let two: Int64 = 19
    static let escape: Int64 = 53
    static let enter: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let backspace: Int64 = 51
    static let arrowUp: Int64 = 126
    static let arrowDown: Int64 = 125
    static let n: Int64 = 45
    static let p: Int64 = 35
}

// Modifiers that, if present alongside cmd, mean "not our gesture" — let them
// pass through to AeroSpace (cmd-shift-1/2 are row moves) and macOS.
private let disallowedModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskHelp, .maskSecondaryFn]

private func aerospacePath() -> String {
    for path in ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"] {
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    return "/opt/homebrew/bin/aerospace"
}

private func workspaceRow(_ workspace: String) -> Int? {
    if workspace.range(of: #"^q(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil { return 0 }
    guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil,
          let character = workspace.dropFirst().first,
          let row = Int(String(character))
    else { return nil }
    return row
}

// MARK: - Model

private struct Candidate: Equatable {
    let workspace: String
    let windowID: String
    let appName: String
    let windowTitle: String
    let bundleID: String
}

// App-name display overrides from the [app_names] config table, keyed by the
// real app name lowercased. An empty value hides the label (icon stays).
private var appNameOverrides: [String: String] = [:]

private func displayAppName(_ appName: String) -> String {
    appNameOverrides[appName.lowercased()] ?? appName
}

private enum Scope: Int, CaseIterable {
    case workspace
    case row
    case all

    var next: Scope { Scope(rawValue: (rawValue + 1) % Scope.allCases.count)! }

    var label: String {
        switch self {
        case .workspace: return "This Workspace"
        case .row: return "This Row"
        case .all: return "All Windows"
        }
    }
}

private var appIconCache: [String: NSImage] = [:]

private func appIcon(bundleID: String) -> NSImage? {
    guard !bundleID.isEmpty else { return nil }
    if let cached = appIconCache[bundleID] { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    appIconCache[bundleID] = icon
    return icon
}

// MARK: - Config

private struct SwitcherConfig {
    var width: CGFloat = 720
    var rowHeight: CGFloat = 30
    var headerHeight: CGFloat = 34
    var maxVisibleRows: Int = 12
    var cornerRadius: CGFloat = 14
    var rowCornerRadius: CGFloat = 7
    var appColumnWidth: CGFloat = 240
    var iconSize: CGFloat = 18
    var numberColumnWidth: CGFloat = 34
    var headerFontSize: CGFloat = 12
    var rowFontSize: CGFloat = 14
    var numberFontSize: CGFloat = 12

    var selectedColor = NSColor(calibratedRed: 0.84, green: 0.42, blue: 0.12, alpha: 0.95)
    var selectedTextColor = NSColor.white.withAlphaComponent(0.98)
    var appTextColor = NSColor.white.withAlphaComponent(0.92)
    var titleTextColor = NSColor.white.withAlphaComponent(0.95)
    var dimTextColor = NSColor.white.withAlphaComponent(0.42)
    var headerTextColor = NSColor.white.withAlphaComponent(0.5)
    var borderColor = NSColor.white.withAlphaComponent(0.12)

    static func load() -> SwitcherConfig {
        var config = SwitcherConfig()
        guard let path = configPath(), let values = readValues(at: path) else { return config }

        config.width = values.cgFloat("width", default: config.width, min: 320, max: 2000)
        config.rowHeight = values.cgFloat("row_height", default: config.rowHeight, min: 18, max: 80)
        config.headerHeight = values.cgFloat("header_height", default: config.headerHeight, min: 0, max: 80)
        config.maxVisibleRows = values.int("max_visible_rows", default: config.maxVisibleRows, min: 3, max: 40)
        config.cornerRadius = values.cgFloat("corner_radius", default: config.cornerRadius, min: 0, max: 40)
        config.rowCornerRadius = values.cgFloat("row_corner_radius", default: config.rowCornerRadius, min: 0, max: 24)
        config.appColumnWidth = values.cgFloat("app_column_width", default: config.appColumnWidth, min: 60, max: 600)
        config.iconSize = values.cgFloat("icon_size", default: config.iconSize, min: 10, max: 48)
        config.numberColumnWidth = values.cgFloat("number_column_width", default: config.numberColumnWidth, min: 0, max: 80)
        config.headerFontSize = values.cgFloat("header_font_size", default: config.headerFontSize, min: 8, max: 24)
        config.rowFontSize = values.cgFloat("row_font_size", default: config.rowFontSize, min: 9, max: 28)
        config.numberFontSize = values.cgFloat("number_font_size", default: config.numberFontSize, min: 8, max: 24)

        config.selectedColor = values.color("selected_color") ?? config.selectedColor
        config.selectedTextColor = values.color("selected_text_color") ?? config.selectedTextColor
        config.appTextColor = values.color("app_text_color") ?? config.appTextColor
        config.titleTextColor = values.color("title_text_color") ?? config.titleTextColor
        config.dimTextColor = values.color("dim_text_color") ?? config.dimTextColor
        config.headerTextColor = values.color("header_text_color") ?? config.headerTextColor
        config.borderColor = values.color("border_color") ?? config.borderColor

        return config
    }

    private static func configPath() -> String? {
        var candidates: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["AEROSPACE_SWITCHER_CONFIG"], !envPath.isEmpty {
            candidates.append(envPath)
        }
        if let executableURL = Bundle.main.executableURL {
            let directory = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("config.toml").path)
        }
        if let resourcePath = Bundle.main.path(forResource: "config", ofType: "toml") {
            candidates.append(resourcePath)
        }
        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/aerospace-switcher/config.toml").path
        )
        return candidates.first { FileManager.default.isReadableFile(atPath: $0) }
    }

    private static func readValues(at path: String) -> [String: String]? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var section = ""
        var values: [String: String] = [:]
        appNameOverrides = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if section == "app_names" {
                appNameOverrides[unquote(key)] = unquote(value)
                continue
            }
            guard section.isEmpty || section == "switcher" else { continue }
            values[key] = value
        }
        return values
    }

    private static func unquote(_ raw: String) -> String {
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return raw }
        return String(raw.dropFirst().dropLast())
    }

    private static func stripComment(_ line: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        for character in line {
            if escaped { result.append(character); escaped = false; continue }
            if character == "\\" { result.append(character); escaped = true; continue }
            if character == "\"" { inString.toggle(); result.append(character); continue }
            if character == "#", !inString { break }
            result.append(character)
        }
        return result
    }
}

private extension Dictionary where Key == String, Value == String {
    func string(_ key: String) -> String? {
        guard let raw = self[key] else { return nil }
        if raw.hasPrefix("\""), raw.hasSuffix("\""),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? String {
            return decoded
        }
        return raw
    }

    func int(_ key: String, default defaultValue: Int, min: Int, max: Int) -> Int {
        guard let value = string(key).flatMap(Int.init) else { return defaultValue }
        return Swift.min(Swift.max(value, min), max)
    }

    func double(_ key: String, default defaultValue: Double, min: Double, max: Double) -> Double {
        guard let value = string(key).flatMap(Double.init) else { return defaultValue }
        return Swift.min(Swift.max(value, min), max)
    }

    func cgFloat(_ key: String, default defaultValue: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        CGFloat(double(key, default: Double(defaultValue), min: Double(min), max: Double(max)))
    }

    func color(_ key: String) -> NSColor? {
        guard let value = string(key) else { return nil }
        return NSColor(hex: value)
    }
}

private extension NSColor {
    convenience init?(hex rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.hasPrefix("0x") || value.hasPrefix("0X") { value.removeFirst(2) }
        if value.count == 3 || value.count == 4 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let red, green, blue, alpha: UInt64
        if value.count == 8 {
            red = (number >> 24) & 0xff; green = (number >> 16) & 0xff
            blue = (number >> 8) & 0xff; alpha = number & 0xff
        } else {
            red = (number >> 16) & 0xff; green = (number >> 8) & 0xff; blue = number & 0xff; alpha = 0xff
        }
        self.init(calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                  blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }
}

// MARK: - AeroSpace client

private final class AeroSpaceClient {
    private let executable = aerospacePath()

    func focusedWorkspace() -> String? {
        guard let output = run(["list-workspaces", "--focused"]) else { return nil }
        for line in output.split(whereSeparator: \.isNewline) {
            let workspace = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if workspaceRow(workspace) != nil { return workspace }
        }
        return nil
    }

    func allWindows() -> [Candidate] {
        guard let output = run(["list-windows", "--all", "--format",
            "%{workspace}\t%{window-id}\t%{app-name}\t%{app-bundle-id}\t%{window-title}"]) else { return [] }
        var result: [Candidate] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { continue }
            let workspace = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let windowID = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let app = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleID = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let title = parts.count > 4 ? parts[4].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !windowID.isEmpty, !app.isEmpty else { continue }
            result.append(Candidate(workspace: workspace, windowID: windowID, appName: app, windowTitle: title, bundleID: bundleID))
        }
        return result.sorted {
            if $0.appName == $1.appName {
                if $0.windowTitle == $1.windowTitle { return $0.windowID < $1.windowID }
                return $0.windowTitle.localizedCaseInsensitiveCompare($1.windowTitle) == .orderedAscending
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    func focusWindow(_ windowID: String) {
        _ = run(["focus", "--window-id", windowID])
    }

    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Fuzzy match

// Case-insensitive subsequence match. Returns nil for no match; higher score is
// a better match (contiguous runs and word-boundary hits are rewarded).
private func fuzzyScore(query: String, text: String) -> Int? {
    let needle = Array(query.lowercased())
    guard !needle.isEmpty else { return 0 }
    let haystack = Array(text.lowercased())
    let rawHaystack = Array(text)

    var score = 0
    var needleIndex = 0
    var lastMatch = -2
    for (index, character) in haystack.enumerated() {
        guard needleIndex < needle.count, character == needle[needleIndex] else { continue }
        if index == lastMatch + 1 { score += 5 } else { score += 1 }
        if index == 0 { score += 8 }
        else if rawHaystack[index - 1] == " " || rawHaystack[index - 1] == "-" || rawHaystack[index - 1] == "/" { score += 6 }
        else if rawHaystack[index].isUppercase { score += 2 }
        lastMatch = index
        needleIndex += 1
    }
    return needleIndex == needle.count ? score : nil
}

// MARK: - List view

private final class SwitcherView: NSView {
    var config: SwitcherConfig { didSet { needsDisplay = true } }

    var candidates: [Candidate] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { if oldValue != selectedIndex { needsDisplay = true } } }
    var scopeLabel = "" { didSet { needsDisplay = true } }
    var searchActive = false { didSet { needsDisplay = true } }
    var query = "" { didSet { needsDisplay = true } }
    var scrollOffset = 0 { didSet { if oldValue != scrollOffset { needsDisplay = true } } }

    var onPick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(frame frameRect: NSRect, config: SwitcherConfig) {
        self.config = config
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.config = SwitcherConfig()
        super.init(coder: coder)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private var visibleRowCount: Int { min(candidates.count, config.maxVisibleRows) }

    private func rowRect(_ visibleIndex: Int) -> NSRect {
        let y = config.headerHeight + CGFloat(visibleIndex) * config.rowHeight
        return NSRect(x: 8, y: y, width: bounds.width - 16, height: config.rowHeight)
    }

    private func candidateIndex(at point: NSPoint) -> Int? {
        guard point.y >= config.headerHeight else { return nil }
        let visibleIndex = Int((point.y - config.headerHeight) / config.rowHeight)
        guard visibleIndex >= 0, visibleIndex < visibleRowCount else { return nil }
        let index = scrollOffset + visibleIndex
        return index < candidates.count ? index : nil
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = candidateIndex(at: point) { onHover?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = candidateIndex(at: point) { onPick?(index) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeader()
        guard !candidates.isEmpty else { drawEmpty(); return }

        for visibleIndex in 0..<visibleRowCount {
            let index = scrollOffset + visibleIndex
            guard index < candidates.count else { break }
            drawRow(candidates[index], number: index + 1, rect: rowRect(visibleIndex), selected: index == selectedIndex)
        }
    }

    private func drawHeader() {
        guard config.headerHeight > 0 else { return }
        let rect = NSRect(x: 16, y: 0, width: bounds.width - 32, height: config.headerHeight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let text: String
        if searchActive {
            text = query.isEmpty ? "Search all windows…" : query
        } else {
            text = scopeLabel
        }
        let color = (searchActive && query.isEmpty) ? config.dimTextColor : config.headerTextColor
        let font = searchActive
            ? NSFont.systemFont(ofSize: config.rowFontSize, weight: .regular)
            : NSFont.systemFont(ofSize: config.headerFontSize, weight: .semibold)

        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        let height = attributed.size().height
        attributed.draw(in: NSRect(x: rect.minX, y: rect.minY + (config.headerHeight - height) / 2,
                                   width: rect.width, height: height))

        // Hairline under the header.
        config.borderColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 12, y: config.headerHeight - 0.5))
        line.line(to: NSPoint(x: bounds.width - 12, y: config.headerHeight - 0.5))
        line.lineWidth = 1
        line.stroke()
    }

    private func drawEmpty() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = searchActive ? "No matches" : "No windows"
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: config.rowFontSize, weight: .regular),
            .foregroundColor: config.dimTextColor,
            .paragraphStyle: paragraph,
        ]).draw(in: NSRect(x: 16, y: config.headerHeight + config.rowHeight / 2,
                           width: bounds.width - 32, height: config.rowHeight))
    }

    private func drawRow(_ candidate: Candidate, number: Int, rect: NSRect, selected: Bool) {
        if selected {
            let bar = NSBezierPath(roundedRect: rect, xRadius: config.rowCornerRadius, yRadius: config.rowCornerRadius)
            config.selectedColor.setFill()
            bar.fill()
        }

        let appColor = selected ? config.selectedTextColor : config.appTextColor
        let titleColor = selected ? config.selectedTextColor : config.titleTextColor
        let numberColor = selected ? config.selectedTextColor.withAlphaComponent(0.85) : config.dimTextColor
        let inset = rect.insetBy(dx: 12, dy: 0)
        let centerY = rect.midY

        // Number (left, dim).
        if config.numberColumnWidth > 0 {
            drawText(String(number), in: NSRect(x: inset.minX, y: 0, width: config.numberColumnWidth, height: rect.height),
                     centerY: centerY, font: NSFont.monospacedDigitSystemFont(ofSize: config.numberFontSize, weight: .regular),
                     color: numberColor, alignment: .left)
        }

        // App name (right-aligned column).
        let appColumnX = inset.minX + config.numberColumnWidth
        drawText(displayAppName(candidate.appName), in: NSRect(x: appColumnX, y: 0, width: config.appColumnWidth, height: rect.height),
                 centerY: centerY, font: NSFont.systemFont(ofSize: config.rowFontSize, weight: .medium),
                 color: appColor, alignment: .right)

        // Icon.
        let iconX = appColumnX + config.appColumnWidth + 10
        if let icon = appIcon(bundleID: candidate.bundleID) {
            icon.draw(in: NSRect(x: iconX, y: centerY - config.iconSize / 2, width: config.iconSize, height: config.iconSize))
        }

        // Window title (fills the rest).
        let titleX = iconX + config.iconSize + 8
        let titleWidth = inset.maxX - titleX
        if titleWidth > 20 {
            let title = candidate.windowTitle.isEmpty ? candidate.appName : candidate.windowTitle
            drawText(title, in: NSRect(x: titleX, y: 0, width: titleWidth, height: rect.height),
                     centerY: centerY, font: NSFont.systemFont(ofSize: config.rowFontSize, weight: .regular),
                     color: titleColor, alignment: .left)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, centerY: CGFloat, font: NSFont, color: NSColor,
                          alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        let height = attributed.size().height
        attributed.draw(in: NSRect(x: rect.minX, y: centerY - height / 2, width: rect.width, height: height))
    }
}

// Borderless panels can't become key by default; search mode needs keystrokes.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: SwitcherConfig
    private let aerospace = AeroSpaceClient()
    private lazy var view = SwitcherView(frame: NSRect(x: 0, y: 0, width: config.width, height: 400), config: config)
    private var panel: KeyablePanel?

    // Cached inventory, refreshed in the background so a trigger is instant.
    private var inventory: [Candidate] = []
    private var focusedWorkspace = "w10"

    // Session state.
    private var active = false           // overlay visible
    private var searchMode = false       // persistent, key, search field
    private var navigated = false        // any selection/scope nav happened this hold
    private var scope: Scope = .workspace
    private var query = ""
    private var selectedIndex = 0
    private var displayed: [Candidate] = []

    private var eventTap: CFMachPort?
    private var swallowedKeys = Set<Int64>()
    private var localKeyMonitor: Any?
    private var clickMonitor: Any?
    private var windowsTimer: Timer?

    override init() {
        self.config = SwitcherConfig.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        view.onPick = { [weak self] index in self?.pick(index) }
        view.onHover = { [weak self] index in self?.setSelection(index) }

        refreshFocusedFromFile()
        refreshInventory()
        windowsTimer = Timer.scheduledTimer(withTimeInterval: windowsPollInterval, repeats: true) { [weak self] _ in
            self?.refreshFocusedFromFile()
            self?.refreshInventory()
        }

        installEventTap()
    }

    // MARK: Panel

    private func createPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: config.width, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let blur = NSVisualEffectView(frame: panel.contentLayoutRect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = config.cornerRadius
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = config.borderColor.cgColor
        blur.autoresizingMask = [.width, .height]

        view.frame = blur.bounds
        view.autoresizingMask = [.width, .height]
        blur.addSubview(view)
        panel.contentView = blur
        self.panel = panel
    }

    // MARK: Inventory

    private func refreshInventory() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let windows = self.aerospace.allWindows()
            DispatchQueue.main.async {
                self.inventory = windows
                if self.active { self.rebuildDisplayed(preserveSelection: true) }
            }
        }
    }

    private func refreshFocusedFromFile() {
        guard let hint = try? String(contentsOfFile: focusedStatePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceRow(hint) != nil
        else { return }
        focusedWorkspace = hint
    }

    private func candidates(for scope: Scope) -> [Candidate] {
        switch scope {
        case .all:
            return inventory
        case .workspace:
            return inventory.filter { $0.workspace == focusedWorkspace }
        case .row:
            guard let row = workspaceRow(focusedWorkspace) else { return inventory }
            return inventory.filter { workspaceRow($0.workspace) == row }
        }
    }

    private func rebuildDisplayed(preserveSelection: Bool) {
        let previous = preserveSelection && selectedIndex < displayed.count ? displayed[selectedIndex] : nil
        var base = candidates(for: scope)

        if searchMode, !query.isEmpty {
            base = base
                .compactMap { candidate -> (Candidate, Int)? in
                    let haystack = "\(candidate.appName) \(candidate.windowTitle)"
                    guard let score = fuzzyScore(query: query, text: haystack) else { return nil }
                    return (candidate, score)
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }

        displayed = base
        if let previous, let index = displayed.firstIndex(of: previous) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(0, displayed.count - 1))
        }
        if displayed.isEmpty { selectedIndex = 0 }
        syncView()
    }

    private func syncView() {
        view.candidates = displayed
        view.selectedIndex = selectedIndex
        view.scopeLabel = scope.label
        view.searchActive = searchMode
        view.query = query
        view.scrollOffset = scrollOffset()
        resizePanel()
    }

    private func scrollOffset() -> Int {
        let maxVisible = config.maxVisibleRows
        guard displayed.count > maxVisible else { return 0 }
        if selectedIndex < maxVisible { return 0 }
        return min(selectedIndex - maxVisible + 1, displayed.count - maxVisible)
    }

    // MARK: Geometry

    private func resizePanel() {
        guard let panel else { return }
        let visibleRows = min(max(displayed.count, 1), config.maxVisibleRows)
        let height = config.headerHeight + CGFloat(visibleRows) * config.rowHeight + 8
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(config.width, screen.width - 80)
        let origin = NSPoint(x: screen.midX - width / 2, y: screen.midY - height / 2 + screen.height * 0.08)
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
    }

    // MARK: Activation / state machine

    private func activate() {
        active = true
        navigated = false
        searchMode = false
        query = ""
        scope = .workspace
        selectedIndex = 0
        rebuildDisplayed(preserveSelection: false)
        refreshInventory()
        panel?.orderFrontRegardless()
    }

    private func cycleScope() {
        navigated = true
        scope = scope.next
        selectedIndex = 0
        rebuildDisplayed(preserveSelection: false)
    }

    private func setSelection(_ index: Int) {
        guard !displayed.isEmpty else { return }
        navigated = true
        selectedIndex = min(max(index, 0), displayed.count - 1)
        syncView()
    }

    private func moveSelection(_ delta: Int) {
        guard !displayed.isEmpty else { return }
        navigated = true
        let count = displayed.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        syncView()
    }

    // Cmd released during the transient hold.
    private func commandReleased() {
        guard active, !searchMode else { return }
        if navigated {
            commitSelection()
        } else {
            enterSearchMode()
        }
    }

    private func commitSelection() {
        let target = selectedIndex < displayed.count ? displayed[selectedIndex] : nil
        dismiss()
        guard let target else { return }
        try? "\(target.workspace)\n".write(toFile: focusedStatePath, atomically: true, encoding: .utf8)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.aerospace.focusWindow(target.windowID)
        }
    }

    private func pick(_ index: Int) {
        selectedIndex = min(max(index, 0), max(0, displayed.count - 1))
        commitSelection()
    }

    private func enterSearchMode() {
        searchMode = true
        scope = .all
        query = ""
        selectedIndex = 0
        rebuildDisplayed(preserveSelection: false)
        panel?.makeKeyAndOrderFront(nil)
        installLocalKeyMonitor()
        installClickMonitor()
    }

    private func dismiss() {
        active = false
        searchMode = false
        navigated = false
        query = ""
        swallowedKeys.removeAll()
        removeLocalKeyMonitor()
        removeClickMonitor()
        panel?.orderOut(nil)
    }

    // MARK: Search-mode keyboard (panel is key)

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleSearchKey(event) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor); localKeyMonitor = nil }
    }

    // Returns true when consumed.
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        let code = Int64(event.keyCode)
        let flags = event.modifierFlags
        let hasCommand = flags.contains(.command)
        let hasControl = flags.contains(.control)

        switch code {
        case Key.escape:
            dismiss(); return true
        case Key.enter, Key.keypadEnter:
            commitSelection(); return true
        case Key.tab:
            cycleScope(); return true
        case Key.arrowUp:
            moveSelection(-1); return true
        case Key.arrowDown:
            moveSelection(1); return true
        case Key.one where hasCommand:
            moveSelection(-1); return true
        case Key.two where hasCommand:
            moveSelection(1); return true
        case Key.p where hasControl:
            moveSelection(-1); return true
        case Key.n where hasControl:
            moveSelection(1); return true
        case Key.backspace:
            if !query.isEmpty { query.removeLast(); rebuildDisplayed(preserveSelection: false) }
            return true
        default:
            break
        }

        // Plain printable characters edit the query.
        if !hasCommand, !hasControl, let characters = event.charactersIgnoringModifiers,
           characters.count == 1, let scalar = characters.unicodeScalars.first,
           scalar.value >= 32, scalar.value != 127 {
            query.append(characters)
            rebuildDisplayed(preserveSelection: false)
            return true
        }
        return true   // swallow everything else while searching
    }

    // Click outside the panel dismisses search mode.
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
    }

    // MARK: Event tap (transient hold phase)

    private func installEventTap() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            fputs("aerospace-switcher: Accessibility permission required; approve the app in System Settings, then restart AeroSpace\n", stderr)
        }

        let mask: CGEventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: switcherEventCallback, userInfo: refcon)

        guard let eventTap else {
            fputs("aerospace-switcher: failed to create event tap; grant Accessibility permission\n", stderr)
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    // Called from the tap thread (main run loop). Returns true to swallow.
    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)
        let cleanCommand = hasCommand && flags.intersection(disallowedModifiers).isEmpty
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .flagsChanged {
            // Only the transient hold resolves on cmd release; search mode has
            // already let go of cmd and confirms with Enter/click instead.
            if active, !searchMode, !hasCommand { commandReleased() }
            return false
        }

        // Swallow the key-up of anything whose key-down we consumed, so no app
        // sees a dangling release.
        if type == .keyUp {
            return swallowedKeys.remove(code) != nil
        }

        guard type == .keyDown else { return false }

        // cmd-tab triggers or cycles in every mode, and is always swallowed so
        // the macOS app switcher never appears.
        if code == Key.tab, cleanCommand {
            if active { cycleScope() } else { activate() }
            swallowedKeys.insert(code)
            return true
        }

        guard active else { return false }

        // cmd-1 / cmd-2 drive the selection in both transient and search mode;
        // swallowing them also keeps AeroSpace's grid bindings from firing while
        // the switcher owns those keys.
        if code == Key.one, cleanCommand { moveSelection(-1); swallowedKeys.insert(code); return true }
        if code == Key.two, cleanCommand { moveSelection(1); swallowedKeys.insert(code); return true }

        // Esc cancels the transient hold without focusing anything.
        if code == Key.escape, !searchMode { dismiss(); swallowedKeys.insert(code); return true }

        // Everything else flows through; in search mode the key panel's local
        // monitor handles typing, arrows, Enter, and Esc.
        return false
    }
}

private func switcherEventCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        delegate.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    return delegate.handleTapEvent(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
