import AppKit
import Foundation

private let workspaceRows = 9
private let workspaceCols = 10
private let statePollInterval: TimeInterval = 0.05
private let focusedPollInterval: TimeInterval = 0.6
private let windowsPollInterval: TimeInterval = 3.0
private let focusedStatePath = "/tmp/aerospace-hud-focused-workspace"
private let missionControlSignalPath = "/tmp/aerospace-mission-control-toggle"
private let autoHideEnabled = ProcessInfo.processInfo.environment["AEROSPACE_HUD_AUTO_HIDE"] != "0"

private enum GridNavigationDirection {
    case up
    case down
    case left
    case right
}

private enum WorkspaceInsertionPosition: Equatable {
    case before
    case after
}

private func workspaceName(row: Int, col: Int) -> String {
    "w\(row)\(col)"
}

private func workspaceRow(_ workspace: String) -> Int? {
    guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil,
          let rowCharacter = workspace.dropFirst().first,
          let row = Int(String(rowCharacter))
    else { return nil }
    return row
}

private func workspaceColumn(_ workspace: String) -> Int? {
    guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil,
          let columnCharacter = workspace.last,
          let column = Int(String(columnCharacter))
    else { return nil }
    return column
}

// Project-lane name shown only in Mission Control. Row 1 defaults to "base";
// every other row defaults to its "wNx" prefix until the user renames it.
private func defaultRowName(_ row: Int) -> String {
    row == 1 ? "base" : "w\(row)x"
}

private func aerospacePath() -> String {
    for path in ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"] {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    return "/opt/homebrew/bin/aerospace"
}

private struct WorkspaceWindow: Equatable {
    let workspace: String
    let windowID: String
    let appName: String
    let windowTitle: String
    let bundleID: String

    func moved(to workspace: String) -> WorkspaceWindow {
        WorkspaceWindow(workspace: workspace, windowID: windowID, appName: appName, windowTitle: windowTitle, bundleID: bundleID)
    }
}

// App-name display overrides from the [app_names] config table, keyed by the
// real app name lowercased. An empty value hides the label (icon stays).
private var appNameOverrides: [String: String] = [:]

private func displayAppName(_ appName: String) -> String {
    appNameOverrides[appName.lowercased()] ?? appName
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

private struct HudConfig {
    var opacity: CGFloat = 0.96
    var autoHideDelay: TimeInterval = 1.6
    var headerText: String = "AeroSpace {workspace}"
    var margin: CGFloat = 14
    var gap: CGFloat = 8
    var headerHeight: CGFloat = 34
    var tileWidth: CGFloat = 82
    var tileHeight: CGFloat = 58
    var minimumWidth: CGFloat = 180
    var screenPadding: CGFloat = 8
    var missionSnapThreshold: CGFloat = 24
    var missionGlassStyle = "clear"
    var missionGlassCornerRadius: CGFloat = 30
    var missionPanelOpacity: CGFloat = 1
    var missionGlassTintColor = NSColor(calibratedWhite: 0.02, alpha: 1)
    var missionGlassTintOpacity: CGFloat = 0.08
    var missionBackgroundColor = NSColor(calibratedWhite: 0.02, alpha: 1)
    var missionBackgroundOpacity: CGFloat = 0.18
    var missionTileColor = NSColor(calibratedWhite: 0.02, alpha: 0.10)
    var missionEmptyTileColor = NSColor(calibratedWhite: 0.02, alpha: 0.045)
    var missionTileBorderColor = NSColor(calibratedWhite: 0.01, alpha: 0.60)
    var missionTileBorderWidth: CGFloat = 1
    var missionTileCornerRadius: CGFloat = 15
    var missionHoverColor = NSColor(calibratedWhite: 1, alpha: 0.075)
    var missionAccentColor = NSColor(calibratedWhite: 0.04, alpha: 0.78)
    var missionAccentBorderColor = NSColor(calibratedWhite: 0.01, alpha: 0.94)
    var missionAccentTextColor = NSColor(calibratedWhite: 0.96, alpha: 1)
    var missionPrimaryTextColor = NSColor.labelColor
    var missionSecondaryTextColor = NSColor.secondaryLabelColor
    var missionRowTextColor = NSColor.secondaryLabelColor
    var backgroundCornerRadius: CGFloat = 12
    var tileCornerRadius: CGFloat = 7
    var labelCornerRadius: CGFloat = 5
    var selectedBorderWidth: CGFloat = 3.5
    var occupiedBorderWidth: CGFloat = 1
    var headerFontSize: CGFloat = 14
    var workspaceFontSize: CGFloat = 10.5
    var appFontSize: CGFloat = 9.5
    var tileLabelMaxApps: Int = 3
    var shadowEnabled: Bool = true
    var showMenuBar: Bool = true
    var backgroundColor = NSColor(calibratedRed: 0.055, green: 0.064, blue: 0.052, alpha: 0.76)
    var backgroundBorderColor = NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.64, alpha: 0.34)
    var tileColor = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.16, alpha: 0.54)
    var selectedColor = NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.18, alpha: 0.98)
    var occupiedBorderColor = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.90, alpha: 0.26)
    var labelBackgroundColor = NSColor(calibratedRed: 0.045, green: 0.052, blue: 0.044, alpha: 0.56)
    var emptyLabelBackgroundColor = NSColor(calibratedRed: 0.045, green: 0.052, blue: 0.044, alpha: 0.38)
    var headerTextColor = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.90, alpha: 0.98)
    var workspaceTextColor = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.91, alpha: 0.98)
    var appTextColor = NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.93, alpha: 0.94)

    static func load() -> HudConfig {
        var config = HudConfig()
        guard let path = configPath(),
              let values = readValues(at: path)
        else { return config }

        config.opacity = values.cgFloat("opacity", default: config.opacity, min: 0.1, max: 1)
        config.autoHideDelay = TimeInterval(values.double("auto_hide_delay", default: config.autoHideDelay, min: 0.1, max: 30))
        config.headerText = values.string("header_text") ?? config.headerText
        config.margin = values.cgFloat("margin", default: config.margin, min: 0, max: 80)
        config.gap = values.cgFloat("gap", default: config.gap, min: 0, max: 48)
        config.headerHeight = values.cgFloat("header_height", default: config.headerHeight, min: 0, max: 120)
        config.tileWidth = values.cgFloat("tile_width", default: config.tileWidth, min: 36, max: 240)
        config.tileHeight = values.cgFloat("tile_height", default: config.tileHeight, min: 28, max: 180)
        config.minimumWidth = values.cgFloat("minimum_width", default: config.minimumWidth, min: 80, max: 1200)
        config.screenPadding = values.cgFloat("screen_padding", default: config.screenPadding, min: 0, max: 80)
        config.missionSnapThreshold = values.cgFloat("mission_snap_threshold", default: config.missionSnapThreshold, min: 0, max: 200)
        if let style = values.string("mission_control.glass_style")?.lowercased(), ["clear", "regular"].contains(style) {
            config.missionGlassStyle = style
        }
        config.missionGlassCornerRadius = values.cgFloat(
            "mission_control.corner_radius",
            default: config.missionGlassCornerRadius,
            min: 0,
            max: 80
        )
        config.missionPanelOpacity = values.cgFloat(
            "mission_control.panel_opacity",
            default: config.missionPanelOpacity,
            min: 0.1,
            max: 1
        )
        config.missionGlassTintOpacity = values.cgFloat(
            "mission_control.glass_tint_opacity",
            default: config.missionGlassTintOpacity,
            min: 0,
            max: 1
        )
        config.missionBackgroundOpacity = values.cgFloat(
            "mission_control.background_opacity",
            default: config.missionBackgroundOpacity,
            min: 0,
            max: 1
        )
        config.missionTileBorderWidth = values.cgFloat(
            "mission_control.tile_border_width",
            default: config.missionTileBorderWidth,
            min: 0,
            max: 8
        )
        config.missionTileCornerRadius = values.cgFloat(
            "mission_control.tile_corner_radius",
            default: config.missionTileCornerRadius,
            min: 0,
            max: 48
        )
        config.backgroundCornerRadius = values.cgFloat("background_corner_radius", default: config.backgroundCornerRadius, min: 0, max: 40)
        config.tileCornerRadius = values.cgFloat("tile_corner_radius", default: config.tileCornerRadius, min: 0, max: 32)
        config.labelCornerRadius = values.cgFloat("label_corner_radius", default: config.labelCornerRadius, min: 0, max: 24)
        config.selectedBorderWidth = values.cgFloat("selected_border_width", default: config.selectedBorderWidth, min: 0, max: 12)
        config.occupiedBorderWidth = values.cgFloat("occupied_border_width", default: config.occupiedBorderWidth, min: 0, max: 8)
        config.headerFontSize = values.cgFloat("header_font_size", default: config.headerFontSize, min: 8, max: 40)
        config.workspaceFontSize = values.cgFloat("workspace_font_size", default: config.workspaceFontSize, min: 6, max: 28)
        config.appFontSize = values.cgFloat("app_font_size", default: config.appFontSize, min: 6, max: 24)
        config.tileLabelMaxApps = values.int("tile_label_max_apps", default: config.tileLabelMaxApps, min: 0, max: 8)
        config.shadowEnabled = values.bool("shadow", default: config.shadowEnabled)
        config.showMenuBar = values.bool("show_menu_bar", default: config.showMenuBar)

        config.missionGlassTintColor = values.color("mission_control.glass_tint_color") ?? config.missionGlassTintColor
        config.missionBackgroundColor = values.color("mission_control.background_color") ?? config.missionBackgroundColor
        config.missionTileColor = values.color("mission_control.tile_color") ?? config.missionTileColor
        config.missionEmptyTileColor = values.color("mission_control.empty_tile_color") ?? config.missionEmptyTileColor
        config.missionTileBorderColor = values.color("mission_control.tile_border_color") ?? config.missionTileBorderColor
        config.missionHoverColor = values.color("mission_control.hover_color") ?? config.missionHoverColor
        config.missionAccentColor = values.color("mission_control.accent_color") ?? config.missionAccentColor
        config.missionAccentBorderColor = values.color("mission_control.accent_border_color") ?? config.missionAccentBorderColor
        config.missionAccentTextColor = values.color("mission_control.accent_text_color") ?? config.missionAccentTextColor
        config.missionPrimaryTextColor = values.color("mission_control.primary_text_color") ?? config.missionPrimaryTextColor
        config.missionSecondaryTextColor = values.color("mission_control.secondary_text_color") ?? config.missionSecondaryTextColor
        config.missionRowTextColor = values.color("mission_control.row_text_color") ?? config.missionRowTextColor
        config.backgroundColor = values.color("background_color") ?? config.backgroundColor
        config.backgroundBorderColor = values.color("background_border_color") ?? config.backgroundBorderColor
        config.tileColor = values.color("tile_color") ?? config.tileColor
        config.selectedColor = values.color("selected_color") ?? config.selectedColor
        config.occupiedBorderColor = values.color("occupied_border_color") ?? config.occupiedBorderColor
        config.labelBackgroundColor = values.color("label_background_color") ?? config.labelBackgroundColor
        config.emptyLabelBackgroundColor = values.color("empty_label_background_color") ?? config.emptyLabelBackgroundColor
        config.headerTextColor = values.color("header_text_color") ?? config.headerTextColor
        config.workspaceTextColor = values.color("workspace_text_color") ?? config.workspaceTextColor
        config.appTextColor = values.color("app_text_color") ?? config.appTextColor

        return config
    }

    static func modificationDate() -> Date? {
        guard let path = configPath(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private static func configPath() -> String? {
        var candidates: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["AEROSPACE_HUD_CONFIG"], !envPath.isEmpty {
            candidates.append(envPath)
        }

        if let executableURL = Bundle.main.executableURL {
            let hudDirectory = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(hudDirectory.appendingPathComponent("config.toml").path)
        }

        if let resourcePath = Bundle.main.path(forResource: "config", ofType: "toml") {
            candidates.append(resourcePath)
        }

        candidates.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/aerospace-hud/config.toml")
                .path
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
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if section == "app_names" {
                appNameOverrides[unquote(key)] = unquote(value)
                continue
            }

            switch section {
            case "", "hud":
                values[key] = value
            case "mission_control":
                values["mission_control.\(key)"] = value
            default:
                continue
            }
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
            if escaped {
                result.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                result.append(character)
                escaped = true
                continue
            }

            if character == "\"" {
                inString.toggle()
                result.append(character)
                continue
            }

            if character == "#", !inString {
                break
            }

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
           let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        {
            return decoded
        }
        return raw
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let value = string(key)?.lowercased() else { return defaultValue }
        switch value {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return defaultValue
        }
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
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }

        if value.count == 3 || value.count == 4 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16)
        else { return nil }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        if value.count == 8 {
            red = (number >> 24) & 0xff
            green = (number >> 16) & 0xff
            blue = (number >> 8) & 0xff
            alpha = number & 0xff
        } else {
            red = (number >> 16) & 0xff
            green = (number >> 8) & 0xff
            blue = number & 0xff
            alpha = 0xff
        }

        self.init(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}

private final class AeroSpaceClient {
    private let executable = aerospacePath()

    func focusedWorkspace() -> String? {
        guard let output = run(["list-workspaces", "--focused"]) else { return nil }

        for line in output.split(whereSeparator: \.isNewline) {
            let workspace = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil {
                return workspace
            }
        }
        return nil
    }

    func windowsByWorkspace() -> [String: [WorkspaceWindow]] {
        guard let output = run(["list-windows", "--all", "--format", "%{workspace}\t%{window-id}\t%{app-name}\t%{app-bundle-id}\t%{window-title}"]) else {
            return [:]
        }

        var result: [String: [WorkspaceWindow]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3 else { continue }

            let workspace = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let windowID = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let app = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleID = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let title = parts.count > 4 ? parts[4].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil,
                  !windowID.isEmpty,
                  !app.isEmpty
            else { continue }

            result[workspace, default: []].append(WorkspaceWindow(workspace: workspace, windowID: windowID, appName: app, windowTitle: title, bundleID: bundleID))
        }
        for workspace in result.keys {
            result[workspace] = result[workspace]?.sorted {
                if $0.appName == $1.appName {
                    if $0.windowTitle == $1.windowTitle {
                        return $0.windowID < $1.windowID
                    }
                    return $0.windowTitle.localizedCaseInsensitiveCompare($1.windowTitle) == .orderedAscending
                }
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
        }
        return result
    }

    func switchWorkspace(_ workspace: String) {
        _ = run(["workspace", workspace])
    }

    func focusWindow(_ window: WorkspaceWindow) {
        _ = run(["focus", "--window-id", window.windowID])
    }

    func moveWindow(_ window: WorkspaceWindow, to workspace: String) -> Bool {
        run(["move-node-to-workspace", "--window-id", window.windowID, workspace]) != nil
    }

    private func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private final class HudView: NSView {
    var config: HudConfig {
        didSet {
            needsDisplay = true
        }
    }

    var onWorkspaceClick: ((String) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?
    var onPointerEnter: (() -> Void)?
    var onPointerExit: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onResetSize: (() -> Void)?

    var focusedWorkspace = "w10" {
        didSet {
            if oldValue != focusedWorkspace {
                needsDisplay = true
            }
        }
    }

    var windowsByWorkspace: [String: [WorkspaceWindow]] = [:] {
        didSet {
            if oldValue != windowsByWorkspace {
                needsDisplay = true
            }
        }
    }

    var visibleRows = 1 {
        didSet {
            if oldValue != visibleRows {
                needsDisplay = true
            }
        }
    }

    var visibleCols = 1 {
        didSet {
            if oldValue != visibleCols {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool { true }

    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownFrameOrigin: NSPoint?
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    init(frame frameRect: NSRect, config: HudConfig) {
        self.config = config
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.config = HudConfig()
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(
            roundedRect: bounds,
            xRadius: config.backgroundCornerRadius,
            yRadius: config.backgroundCornerRadius
        )
        config.backgroundColor.setFill()
        background.fill()
        config.backgroundBorderColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        let metrics = layoutMetrics()

        if config.headerHeight > 0 {
            drawHeader(in: NSRect(x: config.margin, y: config.margin, width: bounds.width - config.margin * 2, height: config.headerHeight))
        }

        for rowIndex in 0..<visibleRows {
            for colIndex in 0..<visibleCols {
                let workspace = workspaceName(row: rowIndex + 1, col: colIndex)
                let rect = tileRect(rowIndex: rowIndex, colIndex: colIndex, metrics: metrics)
                drawTile(workspace: workspace, rect: rect)
            }
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExit?()
    }

    override func mouseDown(with event: NSEvent) {
        onInteractionStart?()
        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownFrameOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenPoint,
              let origin = mouseDownFrameOrigin,
              let window
        else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y

        if abs(dx) > 4 || abs(dy) > 4 {
            didDrag = true
        }

        if didDrag {
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenPoint = nil
            mouseDownFrameOrigin = nil
            didDrag = false
            onInteractionEnd?()
        }

        guard !didDrag else { return }

        let point = convert(event.locationInWindow, from: nil)
        guard let workspace = workspace(at: point) else { return }
        onWorkspaceClick?(workspace)
    }

    override func rightMouseDown(with event: NSEvent) {
        onInteractionStart?()

        let menu = NSMenu()
        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfigFromMenu(_:)),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let resetItem = NSMenuItem(
            title: "Reset Size",
            action: #selector(resetSizeFromMenu(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        let point = convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: reloadItem, at: point, in: self)

        onInteractionEnd?()
    }

    @objc private func reloadConfigFromMenu(_ sender: NSMenuItem) {
        onReloadConfig?()
    }

    @objc private func resetSizeFromMenu(_ sender: NSMenuItem) {
        onResetSize?()
    }

    func preferredHeight(for rowCount: Int) -> CGFloat {
        let rows = CGFloat(max(1, min(workspaceRows, rowCount)))
        return config.margin * 2 + config.headerHeight + config.gap * (rows - 1) + config.tileHeight * rows
    }

    func preferredWidth(for colCount: Int) -> CGFloat {
        let cols = CGFloat(max(1, min(workspaceCols, colCount)))
        let width = config.margin * 2 + config.gap * (cols - 1) + config.tileWidth * cols
        return max(config.minimumWidth, width)
    }

    private struct LayoutMetrics {
        let gridRect: NSRect
        let tileWidth: CGFloat
        let tileHeight: CGFloat
    }

    private func layoutMetrics() -> LayoutMetrics {
        let gridRect = NSRect(
            x: config.margin,
            y: config.margin + config.headerHeight,
            width: bounds.width - config.margin * 2,
            height: bounds.height - config.margin * 2 - config.headerHeight
        )
        let colCount = max(1, visibleCols)
        let tileWidth = (gridRect.width - config.gap * CGFloat(colCount - 1)) / CGFloat(colCount)
        let rowCount = max(1, visibleRows)
        let tileHeight = (gridRect.height - config.gap * CGFloat(rowCount - 1)) / CGFloat(rowCount)

        return LayoutMetrics(gridRect: gridRect, tileWidth: tileWidth, tileHeight: tileHeight)
    }

    private func tileRect(rowIndex: Int, colIndex: Int, metrics: LayoutMetrics) -> NSRect {
        NSRect(
            x: metrics.gridRect.minX + CGFloat(colIndex) * (metrics.tileWidth + config.gap),
            y: metrics.gridRect.minY + CGFloat(rowIndex) * (metrics.tileHeight + config.gap),
            width: metrics.tileWidth,
            height: metrics.tileHeight
        )
    }

    func tileRect(for workspace: String) -> NSRect? {
        guard let row = workspaceRow(workspace),
              let col = workspaceColumn(workspace)
        else { return nil }

        let rowIndex = row - 1
        guard rowIndex >= 0, rowIndex < visibleRows,
              col >= 0, col < visibleCols
        else { return nil }

        return tileRect(rowIndex: rowIndex, colIndex: col, metrics: layoutMetrics())
    }

    private func workspace(at point: NSPoint) -> String? {
        let metrics = layoutMetrics()
        guard point.x >= metrics.gridRect.minX,
              point.y >= metrics.gridRect.minY
        else { return nil }

        let colIndex = Int((point.x - metrics.gridRect.minX) / (metrics.tileWidth + config.gap))
        let rowIndex = Int((point.y - metrics.gridRect.minY) / (metrics.tileHeight + config.gap))

        guard rowIndex >= 0, rowIndex < visibleRows,
              colIndex >= 0, colIndex < visibleCols
        else { return nil }

        let rect = tileRect(rowIndex: rowIndex, colIndex: colIndex, metrics: metrics)
        guard rect.contains(point) else { return nil }

        return workspaceName(row: rowIndex + 1, col: colIndex)
    }

    private func drawHeader(in rect: NSRect) {
        let row = workspaceRow(focusedWorkspace).map(String.init) ?? ""
        let col = workspaceColumn(focusedWorkspace).map(String.init) ?? ""
        let text = config.headerText
            .replacingOccurrences(of: "{workspace}", with: focusedWorkspace)
            .replacingOccurrences(of: "{row}", with: row)
            .replacingOccurrences(of: "{col}", with: col)
        text.draw(
            in: NSRect(x: rect.minX + 1, y: rect.minY + 3, width: rect.width, height: 24),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.headerFontSize, weight: .bold),
                .foregroundColor: config.headerTextColor,
            ]
        )
    }

    private func drawTile(workspace: String, rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: config.tileCornerRadius, yRadius: config.tileCornerRadius)
        config.tileColor.setFill()
        path.fill()

        let apps = appNames(in: workspace)
        drawWorkspaceLabel(workspace, apps: apps, in: rect)

        if workspace == focusedWorkspace {
            config.selectedColor.setStroke()
            let strokeInset = max(0.5, config.selectedBorderWidth / 2)
            let stroke = NSBezierPath(
                roundedRect: rect.insetBy(dx: strokeInset, dy: strokeInset),
                xRadius: max(0, config.tileCornerRadius - 1),
                yRadius: max(0, config.tileCornerRadius - 1)
            )
            stroke.lineWidth = config.selectedBorderWidth
            stroke.stroke()
        } else if !apps.isEmpty, config.occupiedBorderWidth > 0 {
            config.occupiedBorderColor.setStroke()
            let stroke = NSBezierPath(
                roundedRect: rect.insetBy(dx: config.occupiedBorderWidth / 2, dy: config.occupiedBorderWidth / 2),
                xRadius: config.tileCornerRadius,
                yRadius: config.tileCornerRadius
            )
            stroke.lineWidth = config.occupiedBorderWidth
            stroke.stroke()
        }
    }

    private func appNames(in workspace: String) -> [String] {
        let names = (windowsByWorkspace[workspace] ?? []).compactMap { window -> String? in
            let display = displayAppName(window.appName)
            return display.isEmpty ? nil : display
        }
        return Array(Set(names)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func drawWorkspaceLabel(_ workspace: String, apps: [String], in rect: NSRect) {
        let inset = rect.insetBy(dx: 8, dy: 7)
        let labelHeight: CGFloat = apps.isEmpty ? 18 : min(42, inset.height)
        let labelRect = NSRect(x: inset.minX - 4, y: inset.minY - 3, width: inset.width + 8, height: labelHeight)
        let labelBackground = NSBezierPath(roundedRect: labelRect, xRadius: config.labelCornerRadius, yRadius: config.labelCornerRadius)
        (apps.isEmpty ? config.emptyLabelBackgroundColor : config.labelBackgroundColor).setFill()
        labelBackground.fill()

        workspace.draw(
            in: NSRect(x: inset.minX, y: inset.minY, width: inset.width, height: 13),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.workspaceFontSize, weight: .semibold),
                .foregroundColor: config.workspaceTextColor,
            ]
        )

        guard !apps.isEmpty else { return }

        let label = apps.prefix(config.tileLabelMaxApps).joined(separator: "\n")
        guard !label.isEmpty else { return }
        label.draw(
            in: NSRect(x: inset.minX, y: inset.minY + 17, width: inset.width, height: inset.height - 17),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: config.appFontSize, weight: .semibold),
                .foregroundColor: config.appTextColor,
            ]
        )
    }
}

private final class MissionControlView: NSView {
    var config: HudConfig {
        didSet {
            // Mission Control has no header bar — reclaim that space for tiles.
            config.headerHeight = 0
            needsDisplay = true
        }
    }

    var onWorkspaceClick: ((String) -> Void)?
    var onWindowClick: ((WorkspaceWindow) -> Void)?
    var onWindowMove: ((WorkspaceWindow, String) -> Void)?
    var onInsertWorkspace: ((String, WorkspaceInsertionPosition) -> Void)?
    var onInteractionStart: (() -> Void)?
    var onInteractionEnd: (() -> Void)?
    var onPointerEnter: (() -> Void)?
    var onPointerExit: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onResetSize: (() -> Void)?
    var onRowNameCommitted: ((Int, String) -> Void)?
    var onReorderRows: ((Int, Int) -> Void)?
    var onKeyboardWorkspaceNavigate: ((String) -> Void)?
    var onKeyboardDismiss: (() -> Void)?

    // User-set project-lane names, keyed by grid row (1..9). Rows without an
    // entry fall back to `defaultRowName`. Persisted by the AppDelegate.
    var rowNames: [Int: String] = [:] {
        didSet {
            if oldValue != rowNames {
                needsDisplay = true
            }
        }
    }

    // Inline rename: a text field overlaid on the row band while editing.
    private var rowEditor: NSTextField?
    private var editingRow: Int?

    // Row reorder drag: a rail press that moves vertically picks up the whole
    // project lane; releasing drops it into the nearest slot (others shift).
    private var draggedRow: Int?
    private var draggedRowStartPoint: NSPoint?
    private var draggedRowCurrentY: CGFloat?
    private var rowDragTarget: Int?

    private func displayRowName(_ row: Int) -> String {
        if let name = rowNames[row], !name.isEmpty { return name }
        return defaultRowName(row)
    }

    var focusedWorkspace = "w10" {
        didSet {
            if oldValue != focusedWorkspace {
                needsDisplay = true
            }
        }
    }

    var windowsByWorkspace: [String: [WorkspaceWindow]] = [:] {
        didSet {
            if oldValue != windowsByWorkspace {
                needsDisplay = true
            }
        }
    }

    var visibleRows = 1 {
        didSet {
            if oldValue != visibleRows {
                needsDisplay = true
            }
        }
    }

    var visibleCols = 1 {
        didSet {
            if oldValue != visibleCols {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // NSGlassEffectView otherwise remaps custom content colors for adaptive
    // legibility. Mission Control exposes literal TOML color tokens, so keep
    // glass/lensing in the parent while drawing this content without vibrancy.
    override var allowsVibrancy: Bool { false }

    override func keyDown(with event: NSEvent) {
        // Escape closes Mission Control regardless of active modifiers.
        if event.keyCode == 53 {
            onKeyboardDismiss?()
            return
        }

        if let direction = keyboardNavigationDirection(for: event) {
            if let workspace = adjacentWorkspace(for: direction) {
                onKeyboardWorkspaceNavigate?(workspace)
            }
            return
        }

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else {
            super.keyDown(with: event)
            return
        }

        // Return, Space, and numeric-keypad Enter activate the highlighted tile.
        switch event.keyCode {
        case 36, 49, 76:
            onWorkspaceClick?(focusedWorkspace)
        default:
            super.keyDown(with: event)
        }
    }

    // Mission Control is content inside one native Liquid Glass navigation
    // plane. Tiles and chips use semantic fills rather than nested glass, which
    // preserves hierarchy and lets AppKit adapt the material to its environment.
    fileprivate enum Style {
        static let chipRadius: CGFloat = 8
        static let pad: CGFloat = 13
        static let badgeHeight: CGFloat = 16
        static let rowHeight: CGFloat = 24
        static let rowGap: CGFloat = 4
        static let railWidth: CGFloat = 30
    }

    // Overflow-strip icon under the pointer: shows its app name as a tooltip.
    private var hoveredOverflowIcon: (window: WorkspaceWindow, rect: NSRect)?
    private var hoveredWindowID: String?
    private var tooltipProgress: CGFloat = 0
    private var tooltipTimer: Timer?

    private var mouseDownScreenPoint: NSPoint?
    private var mouseDownFrameOrigin: NSPoint?
    private var mouseDownViewPoint: NSPoint?
    private var didDrag = false
    private var suppressWorkspaceClickOnMouseUp = false
    private var trackingArea: NSTrackingArea?
    private var draggedWindow: WorkspaceWindow?
    private var draggedWindowSourceWorkspace: String?
    private var draggedWindowOffset = NSPoint(x: 0, y: 0)
    private var draggedWindowSize = NSSize(width: 0, height: 0)
    private var draggedWindowPoint: NSPoint?
    private var dragTargetWorkspace: String?

    // Drag-to-bottom reveal: pressing a window drag against the bottom edge
    // reveals one empty row below as drop targets. Collapsed again if the drop
    // lands elsewhere or the drag is cancelled.
    private var dragRevealedRow = false
    private let dragRevealBand: CGFloat = 48

    // Manual edge/corner resize (borderless windows don't resize natively).
    private struct ResizeEdges { var left = false; var right = false; var top = false; var bottom = false }
    private let resizeMargin: CGFloat = 7
    private let resizeMinSize = NSSize(width: 360, height: 240)
    private var activeResizeEdges: ResizeEdges?
    private var resizeStartMouse: NSPoint?
    private var resizeStartFrame: NSRect?

    // Mission Control shows only active row/column values. A row or column is
    // active when at least one workspace in it contains a window; empty cells
    // inside that sparse cross-product remain drop targets.
    private var baseOriginRow = 1
    private var baseOriginCol = 0
    private var baseRows = 1
    private var baseCols = 1
    var gridOriginRow = 1
    var gridOriginCol = 0
    var visibleRowValues = [1]
    var visibleColValues = [0]

    // Edge "+" affordance: hover near an edge ~1s to reveal a button that adds
    // a transient row/col, so a window can be dragged into a new workspace.
    private enum GridEdge: Equatable { case top, bottom, left, right }
    private var plusHoverEdge: GridEdge?
    private var activePlusEdge: GridEdge?
    private var plusTimer: Timer?
    private let plusBandInner: CGFloat = 8
    private let plusBandOuter: CGFloat = 64
    private let plusButtonSize: CGFloat = 30

    init(frame frameRect: NSRect, config: HudConfig) {
        self.config = config
        super.init(frame: frameRect)
        observeAccessibilityOptions()
    }

    required init?(coder: NSCoder) {
        self.config = HudConfig()
        super.init(coder: coder)
        observeAccessibilityOptions()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var selectionFill: NSColor {
        config.missionAccentColor
    }

    private var selectionBorder: NSColor {
        config.missionAccentBorderColor
    }

    private var selectionText: NSColor {
        config.missionAccentTextColor
    }

    private var selectionSecondaryText: NSColor {
        config.missionAccentTextColor.withAlphaComponent(0.78)
    }

    private var tileRadius: CGFloat {
        config.missionTileCornerRadius
    }

    private func tileFill(empty: Bool) -> NSColor {
        let color = empty ? config.missionEmptyTileColor : config.missionTileColor
        if reduceTransparency {
            return color.withAlphaComponent(empty ? 0.58 : 0.82)
        }
        return color
    }

    private var tileBorderColor: NSColor {
        increaseContrast
            ? NSColor.labelColor.withAlphaComponent(0.62)
            : config.missionTileBorderColor
    }

    private var primaryTextColor: NSColor {
        config.missionPrimaryTextColor
    }

    private var secondaryTextColor: NSColor {
        config.missionSecondaryTextColor
    }

    private func observeAccessibilityOptions() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDisplayOptionsChanged() {
        stopTooltipAnimation()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Exact configurable color layer inside native glass. NSGlassEffectView
        // tint remains adaptive; this backing makes explicit background choices
        // deterministic while preserving lensing underneath at lower opacities.
        if config.missionBackgroundOpacity > 0 {
            config.missionBackgroundColor
                .withAlphaComponent(config.missionBackgroundOpacity)
                .setFill()
            NSBezierPath(
                roundedRect: bounds,
                xRadius: config.missionGlassCornerRadius,
                yRadius: config.missionGlassCornerRadius
            ).fill()
        }

        // Background, lensing, and rounded corners come from NSGlassEffectView.
        // This view draws only content-layer fills and navigation state.
        let metrics = layoutMetrics()

        for rowIndex in 0..<visibleRows {
            for colIndex in 0..<visibleCols {
                let row = visibleRowValues[rowIndex]
                let col = visibleColValues[colIndex]
                guard isCellVisible(row: row, col: col) else { continue }
                let workspace = workspaceName(row: row, col: col)
                let rect = tileRect(rowIndex: rowIndex, colIndex: colIndex, metrics: metrics)
                drawTile(workspace: workspace, rect: rect)
            }
            let row = visibleRowValues[rowIndex]
            drawRowName(displayRowName(row), row: row, in: railRect(rowIndex: rowIndex, metrics: metrics))
        }

        drawRowDrag(metrics: metrics)
        drawPlusButton()
        // Tooltip hides while a drag is in flight (it would trail the cursor).
        if let hovered = hoveredOverflowIcon, draggedWindow == nil, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setAlpha(tooltipProgress)
            ctx.translateBy(x: 0, y: (1 - tooltipProgress) * 4)   // rise as it fades in
            drawOverflowTooltip(hovered.window, near: hovered.rect)
            ctx.restoreGState()
        }
        drawDraggedWindow()
    }

    // The active row/column set is reset every time Mission Control opens.
    func setGrid(rows: [Int], cols: [Int]) {
        teardownEditor()
        draggedRow = nil
        draggedRowStartPoint = nil
        draggedRowCurrentY = nil
        rowDragTarget = nil
        dragRevealedRow = false
        hoveredOverflowIcon = nil
        stopTooltipAnimation()

        let rowValues = Array(Set(rows.filter { 1...workspaceRows ~= $0 })).sorted()
        let colValues = Array(Set(cols.filter { 0..<workspaceCols ~= $0 })).sorted()
        visibleRowValues = rowValues.isEmpty ? [1] : rowValues
        visibleColValues = colValues.isEmpty ? [0] : colValues

        baseOriginRow = visibleRowValues.first ?? 1
        baseOriginCol = visibleColValues.first ?? 0
        baseRows = visibleRowValues.count
        baseCols = visibleColValues.count
        gridOriginRow = baseOriginRow
        gridOriginCol = baseOriginCol
        visibleRows = visibleRowValues.count
        visibleCols = visibleColValues.count
        clearPlusButton()
        needsDisplay = true
    }

    private func keyboardNavigationDirection(for event: NSEvent) -> GridNavigationDirection? {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return nil }

        // macOS virtual key codes: left, right, down, up. Arrow events can carry
        // the .function modifier, so resolve them before filtering Fn+WASD.
        switch event.keyCode {
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        default: break
        }

        guard !event.modifierFlags.contains(.function) else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": return .up
        case "a": return .left
        case "s": return .down
        case "d": return .right
        default: return nil
        }
    }

    private func adjacentWorkspace(for direction: GridNavigationDirection) -> String? {
        guard let row = workspaceRow(focusedWorkspace),
              let col = workspaceColumn(focusedWorkspace),
              let rowIndex = visibleRowValues.firstIndex(of: row),
              let colIndex = visibleColValues.firstIndex(of: col)
        else { return nil }

        let nextRowIndex: Int
        let nextColIndex: Int
        switch direction {
        case .up:
            nextRowIndex = max(0, rowIndex - 1)
            nextColIndex = colIndex
        case .down:
            nextRowIndex = min(visibleRowValues.count - 1, rowIndex + 1)
            nextColIndex = colIndex
        case .left:
            nextRowIndex = rowIndex
            nextColIndex = max(0, colIndex - 1)
        case .right:
            nextRowIndex = rowIndex
            nextColIndex = min(visibleColValues.count - 1, colIndex + 1)
        }

        guard nextRowIndex != rowIndex || nextColIndex != colIndex else { return nil }
        return workspaceName(row: visibleRowValues[nextRowIndex], col: visibleColValues[nextColIndex])
    }

    // Every Mission Control cell is painted and hit-testable so empty
    // workspaces are visible drop targets.
    private func isCellVisible(row: Int, col: Int) -> Bool {
        true
    }

    private func clearPlusButton() {
        plusTimer?.invalidate()
        plusTimer = nil
        plusHoverEdge = nil
        activePlusEdge = nil
    }

    private func canExpand(_ edge: GridEdge) -> Bool {
        switch edge {
        case .right:  return (visibleColValues.max() ?? 0) < workspaceCols - 1
        case .left:   return (visibleColValues.min() ?? 0) > 0
        case .bottom: return (visibleRowValues.max() ?? 1) < workspaceRows
        case .top:    return (visibleRowValues.min() ?? 1) > 1
        }
    }

    private func expand(_ edge: GridEdge) {
        guard canExpand(edge) else { return }
        switch edge {
        case .right:
            let next = min(workspaceCols - 1, (visibleColValues.max() ?? 0) + 1)
            if !visibleColValues.contains(next) { visibleColValues.append(next) }
        case .bottom:
            let next = min(workspaceRows, (visibleRowValues.max() ?? 1) + 1)
            if !visibleRowValues.contains(next) { visibleRowValues.append(next) }
        case .left:
            let next = max(0, (visibleColValues.min() ?? 0) - 1)
            if !visibleColValues.contains(next) { visibleColValues.insert(next, at: 0) }
        case .top:
            let next = max(1, (visibleRowValues.min() ?? 1) - 1)
            if !visibleRowValues.contains(next) { visibleRowValues.insert(next, at: 0) }
        }
        visibleRowValues.sort()
        visibleColValues.sort()
        gridOriginRow = visibleRowValues.first ?? 1
        gridOriginCol = visibleColValues.first ?? 0
        visibleRows = visibleRowValues.count
        visibleCols = visibleColValues.count
        clearPlusButton()
        needsDisplay = true
    }

    // Which edge the pointer is hovering near (mid-edge only, clear of the
    // corner-resize zones) and that still has room to grow.
    private func plusEdge(at point: NSPoint) -> GridEdge? {
        let yCentral = point.y > bounds.minY + bounds.height * 0.2
            && point.y < bounds.maxY - bounds.height * 0.2
        let xCentral = point.x > bounds.minX + bounds.width * 0.2
            && point.x < bounds.maxX - bounds.width * 0.2

        if yCentral {
            if point.x >= bounds.maxX - plusBandOuter, point.x <= bounds.maxX - plusBandInner,
               canExpand(.right) { return .right }
            if point.x <= bounds.minX + plusBandOuter, point.x >= bounds.minX + plusBandInner,
               canExpand(.left) { return .left }
        }
        if xCentral {
            // Flipped coords: the bottom edge is max-y, the top edge is min-y.
            if point.y >= bounds.maxY - plusBandOuter, point.y <= bounds.maxY - plusBandInner,
               canExpand(.bottom) { return .bottom }
            if point.y <= bounds.minY + plusBandOuter, point.y >= bounds.minY + plusBandInner,
               canExpand(.top) { return .top }
        }
        return nil
    }

    private func plusButtonRect(for edge: GridEdge) -> NSRect {
        let inset = plusButtonSize / 2 + 8
        let center: NSPoint
        switch edge {
        case .right:  center = NSPoint(x: bounds.maxX - inset, y: bounds.midY)
        case .left:   center = NSPoint(x: bounds.minX + inset, y: bounds.midY)
        case .bottom: center = NSPoint(x: bounds.midX, y: bounds.maxY - inset)
        case .top:    center = NSPoint(x: bounds.midX, y: bounds.minY + inset)
        }
        return NSRect(
            x: center.x - plusButtonSize / 2,
            y: center.y - plusButtonSize / 2,
            width: plusButtonSize,
            height: plusButtonSize
        )
    }

    private func drawPlusButton() {
        guard let edge = activePlusEdge else { return }
        let rect = plusButtonRect(for: edge)

        selectionFill.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.labelColor.withAlphaComponent(0.24).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: NSColor.alternateSelectedControlTextColor,
        ]
        let size = ("+" as NSString).size(withAttributes: attrs)
        "+".draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func updatePlusHover(at point: NSPoint) {
        if draggedWindow != nil || activeResizeEdges != nil { return }

        // Keep the button while the pointer rests on it.
        if let edge = activePlusEdge, plusButtonRect(for: edge).contains(point) { return }

        let edge = plusEdge(at: point)
        if edge == plusHoverEdge { return }
        plusHoverEdge = edge
        plusTimer?.invalidate()
        plusTimer = nil

        if activePlusEdge != nil, edge != activePlusEdge {
            activePlusEdge = nil
            needsDisplay = true
        }

        guard let edge else { return }
        plusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.activePlusEdge = edge
            self.plusTimer = nil
            self.needsDisplay = true
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if activePlusEdge != nil || plusHoverEdge != nil {
            clearPlusButton()
            needsDisplay = true
        }
        if hoveredOverflowIcon != nil {
            hoveredOverflowIcon = nil
            stopTooltipAnimation()
            needsDisplay = true
        }
        if hoveredWindowID != nil {
            hoveredWindowID = nil
            needsDisplay = true
        }
        onPointerExit?()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateOverflowHover(at: point)
        let nextHoveredWindowID = window(at: point)?.window.windowID
        if nextHoveredWindowID != hoveredWindowID {
            hoveredWindowID = nextHoveredWindowID
            needsDisplay = true
        }

        // A revealed + button takes pointer priority over edge-resize cursors.
        if let edge = activePlusEdge, plusButtonRect(for: edge).contains(point) {
            NSCursor.pointingHand.set()
            return
        }

        if let edges = resizeEdges(at: point) {
            resizeCursor(for: edges).set()
        } else if nextHoveredWindowID != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }

        updatePlusHover(at: point)
    }

    // Which window edges/corner the point is close enough to grab for resizing.
    private func resizeEdges(at point: NSPoint) -> ResizeEdges? {
        var edges = ResizeEdges()
        edges.left = point.x <= bounds.minX + resizeMargin
        edges.right = point.x >= bounds.maxX - resizeMargin
        edges.top = point.y <= bounds.minY + resizeMargin       // flipped: small y = top
        edges.bottom = point.y >= bounds.maxY - resizeMargin
        return (edges.left || edges.right || edges.top || edges.bottom) ? edges : nil
    }

    private func resizeCursor(for edges: ResizeEdges) -> NSCursor {
        let horizontal = edges.left || edges.right
        let vertical = edges.top || edges.bottom
        if horizontal && !vertical { return .resizeLeftRight }
        if vertical && !horizontal { return .resizeUpDown }
        return .crosshair   // corner (AppKit has no public diagonal-resize cursor)
    }

    override func mouseDown(with event: NSEvent) {
        onInteractionStart?()
        let point = convert(event.locationInWindow, from: nil)

        // Dismiss any overflow tooltip so it doesn't trail a drag.
        if hoveredOverflowIcon != nil {
            hoveredOverflowIcon = nil
            stopTooltipAnimation()
        }
        hoveredWindowID = nil

        // Any click outside the active editor commits the in-progress rename
        // before this click is otherwise handled.
        if rowEditor != nil {
            finishEditing()
        }

        if let edge = activePlusEdge, plusButtonRect(for: edge).contains(point) {
            suppressWorkspaceClickOnMouseUp = true
            expand(edge)
            return
        }
        if activePlusEdge != nil { needsDisplay = true }
        clearPlusButton()

        if let edges = resizeEdges(at: point), let window {
            activeResizeEdges = edges
            resizeStartMouse = NSEvent.mouseLocation
            resizeStartFrame = window.frame
            return
        }

        if let row = railRow(at: point) {
            draggedRow = row
            draggedRowStartPoint = point
            draggedRowCurrentY = nil
            rowDragTarget = nil
            didDrag = false
            return
        }

        if let hit = window(at: point) {
            mouseDownScreenPoint = nil
            mouseDownFrameOrigin = nil
            mouseDownViewPoint = point
            didDrag = false
            draggedWindow = hit.window
            draggedWindowSourceWorkspace = hit.workspace
            draggedWindowOffset = NSPoint(x: point.x - hit.rect.minX, y: point.y - hit.rect.minY)
            draggedWindowSize = hit.rect.size
            draggedWindowPoint = point
            dragTargetWorkspace = hit.workspace
            return
        }

        mouseDownScreenPoint = NSEvent.mouseLocation
        mouseDownFrameOrigin = window?.frame.origin
        mouseDownViewPoint = point
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let edges = activeResizeEdges,
           let start = resizeStartMouse,
           let startFrame = resizeStartFrame,
           let window {
            let current = NSEvent.mouseLocation
            let dx = current.x - start.x
            let dy = current.y - start.y
            var frame = startFrame

            // Window frame is screen coords (y-up); the view is flipped, so its
            // top edge is the window's max-y and its bottom edge the origin.
            if edges.right { frame.size.width = startFrame.width + dx }
            if edges.left { frame.origin.x = startFrame.minX + dx; frame.size.width = startFrame.width - dx }
            if edges.top { frame.size.height = startFrame.height + dy }
            if edges.bottom { frame.origin.y = startFrame.minY + dy; frame.size.height = startFrame.height - dy }

            if frame.size.width < resizeMinSize.width {
                if edges.left { frame.origin.x = startFrame.maxX - resizeMinSize.width }
                frame.size.width = resizeMinSize.width
            }
            if frame.size.height < resizeMinSize.height {
                if edges.bottom { frame.origin.y = startFrame.maxY - resizeMinSize.height }
                frame.size.height = resizeMinSize.height
            }

            window.setFrame(frame, display: true)
            return
        }

        if draggedRow != nil {
            guard let start = draggedRowStartPoint else { return }
            if abs(point.y - start.y) > 4 || abs(point.x - start.x) > 4 {
                didDrag = true
            }
            if didDrag {
                draggedRowCurrentY = point.y
                rowDragTarget = rowSlot(at: point.y)
                NSCursor.closedHand.set()
                needsDisplay = true
            }
            return
        }

        if draggedWindow != nil {
            guard let start = mouseDownViewPoint else { return }
            let dx = point.x - start.x
            let dy = point.y - start.y

            if abs(dx) > 4 || abs(dy) > 4 {
                didDrag = true
            }

            if didDrag {
                maybeRevealDropRow(at: point)
                draggedWindowPoint = point
                dragTargetWorkspace = workspace(at: point)
                NSCursor.closedHand.set()
                needsDisplay = true
            }
            return
        }

        guard let start = mouseDownScreenPoint,
              let origin = mouseDownFrameOrigin,
              let window
        else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y

        if abs(dx) > 4 || abs(dy) > 4 {
            didDrag = true
        }

        if didDrag {
            let proposedX = origin.x + dx
            window.setFrameOrigin(NSPoint(x: snappedOriginX(proposedX, window: window), y: origin.y + dy))
        }
    }

    // Spotlight-style magnet: while dragging, the panel sticks to the screen's
    // horizontal center once its own center lands within the snap threshold, so
    // it has to be pulled past the threshold to break free. Releasing on the
    // snap saves the centered frame, so it stays sticky across opens.
    private func snappedOriginX(_ proposedX: CGFloat, window: NSWindow) -> CGFloat {
        let threshold = config.missionSnapThreshold
        guard threshold > 0, let screen = window.screen ?? NSScreen.main else { return proposedX }
        let centeredX = screen.visibleFrame.midX - window.frame.width / 2
        return abs(proposedX - centeredX) <= threshold ? centeredX : proposedX
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenPoint = nil
            mouseDownFrameOrigin = nil
            mouseDownViewPoint = nil
            draggedWindow = nil
            draggedWindowSourceWorkspace = nil
            draggedWindowOffset = NSPoint(x: 0, y: 0)
            draggedWindowSize = NSSize(width: 0, height: 0)
            draggedWindowPoint = nil
            dragTargetWorkspace = nil
            activeResizeEdges = nil
            resizeStartMouse = nil
            resizeStartFrame = nil
            draggedRow = nil
            draggedRowStartPoint = nil
            draggedRowCurrentY = nil
            rowDragTarget = nil
            dragRevealedRow = false
            didDrag = false
            suppressWorkspaceClickOnMouseUp = false
            NSCursor.arrow.set()
            onInteractionEnd?()
            needsDisplay = true
        }

        // A resize gesture must not fall through to workspace-click handling.
        if activeResizeEdges != nil { return }

        // A rail press: a drag reorders the lane, a plain click renames it.
        if let draggedRow {
            if didDrag, let target = rowDragTarget, target != draggedRow {
                onReorderRows?(draggedRow, target)
            } else if !didDrag {
                beginRenaming(row: draggedRow)
            }
            return
        }

        if let draggedWindow {
            let point = convert(event.locationInWindow, from: nil)
            let drop = workspace(at: point)
            // A drag-revealed row survives only if the window lands in it;
            // otherwise collapse it so the grid returns to its prior shape.
            let revealedRow = dragRevealedRow ? visibleRowValues.last : nil
            let usedRevealedRow = revealedRow != nil && drop.flatMap(workspaceRow) == revealedRow

            if didDrag,
               let workspace = drop,
               workspace != draggedWindowSourceWorkspace
            {
                onWindowMove?(draggedWindow, workspace)
                if dragRevealedRow, !usedRevealedRow { collapseRevealedDropRow(revealedRow) }
                return
            }

            if dragRevealedRow { collapseRevealedDropRow(revealedRow) }
            if !didDrag {
                onWindowClick?(draggedWindow)
            }
            return
        }

        guard !didDrag else { return }
        if suppressWorkspaceClickOnMouseUp { return }

        let point = convert(event.locationInWindow, from: nil)
        guard let workspace = workspace(at: point) else { return }
        onWorkspaceClick?(workspace)
    }

    override func rightMouseDown(with event: NSEvent) {
        onInteractionStart?()

        let menu = NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        var positioningItem: NSMenuItem?

        if let workspace = workspace(at: point) {
            let beforeItem = NSMenuItem(
                title: "Add Workspace Before",
                action: #selector(insertWorkspaceBeforeFromMenu(_:)),
                keyEquivalent: ""
            )
            beforeItem.target = self
            beforeItem.representedObject = workspace
            beforeItem.isEnabled = canInsertWorkspace(around: workspace, position: .before)
            menu.addItem(beforeItem)
            positioningItem = beforeItem

            let afterItem = NSMenuItem(
                title: "Add Workspace After",
                action: #selector(insertWorkspaceAfterFromMenu(_:)),
                keyEquivalent: ""
            )
            afterItem.target = self
            afterItem.representedObject = workspace
            afterItem.isEnabled = canInsertWorkspace(around: workspace, position: .after)
            menu.addItem(afterItem)
            menu.addItem(.separator())
        }

        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfigFromMenu(_:)),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let resetItem = NSMenuItem(
            title: "Reset Size",
            action: #selector(resetSizeFromMenu(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.popUp(positioning: positioningItem ?? reloadItem, at: point, in: self)

        onInteractionEnd?()
    }

    @objc private func insertWorkspaceBeforeFromMenu(_ sender: NSMenuItem) {
        guard let workspace = sender.representedObject as? String else { return }
        onInsertWorkspace?(workspace, .before)
    }

    @objc private func insertWorkspaceAfterFromMenu(_ sender: NSMenuItem) {
        guard let workspace = sender.representedObject as? String else { return }
        onInsertWorkspace?(workspace, .after)
    }

    @objc private func reloadConfigFromMenu(_ sender: NSMenuItem) {
        onReloadConfig?()
    }

    @objc private func resetSizeFromMenu(_ sender: NSMenuItem) {
        onResetSize?()
    }

    func preferredHeight(for rowCount: Int) -> CGFloat {
        let rows = CGFloat(max(1, min(workspaceRows, rowCount)))
        return config.margin * 2 + config.headerHeight + config.gap * (rows - 1) + config.tileHeight * rows
    }

    func preferredWidth(for colCount: Int) -> CGFloat {
        let cols = CGFloat(max(1, min(workspaceCols, colCount)))
        let width = config.margin * 2 + config.gap * (cols - 1) + config.tileWidth * cols
        return max(config.minimumWidth, width)
    }

    private struct LayoutMetrics {
        let gridRect: NSRect
        let tileWidth: CGFloat
        let tileHeight: CGFloat
    }

    private func layoutMetrics() -> LayoutMetrics {
        // Reserve a left rail for vertical row names; the tile grid starts to
        // its right so hit-testing and drawing stay aligned.
        let gridRect = NSRect(
            x: config.margin + Style.railWidth,
            y: config.margin + config.headerHeight,
            width: bounds.width - config.margin * 2 - Style.railWidth,
            height: bounds.height - config.margin * 2 - config.headerHeight
        )
        let colCount = max(1, visibleCols)
        let tileWidth = (gridRect.width - config.gap * CGFloat(colCount - 1)) / CGFloat(colCount)
        let rowCount = max(1, visibleRows)
        let tileHeight = (gridRect.height - config.gap * CGFloat(rowCount - 1)) / CGFloat(rowCount)

        return LayoutMetrics(gridRect: gridRect, tileWidth: tileWidth, tileHeight: tileHeight)
    }

    private func tileRect(rowIndex: Int, colIndex: Int, metrics: LayoutMetrics) -> NSRect {
        NSRect(
            x: metrics.gridRect.minX + CGFloat(colIndex) * (metrics.tileWidth + config.gap),
            y: metrics.gridRect.minY + CGFloat(rowIndex) * (metrics.tileHeight + config.gap),
            width: metrics.tileWidth,
            height: metrics.tileHeight
        )
    }

    // Left-rail band for a row's vertical name, aligned to that row's tiles.
    private func railRect(rowIndex: Int, metrics: LayoutMetrics) -> NSRect {
        let y = metrics.gridRect.minY + CGFloat(rowIndex) * (metrics.tileHeight + config.gap)
        return NSRect(x: config.margin, y: y, width: Style.railWidth - 4, height: metrics.tileHeight)
    }

    // Which row's rail label (if any) the point falls on — used for rename.
    private func railRow(at point: NSPoint) -> Int? {
        let metrics = layoutMetrics()
        guard point.x >= config.margin, point.x < metrics.gridRect.minX,
              point.y >= metrics.gridRect.minY
        else { return nil }

        let unit = metrics.tileHeight + config.gap
        let rowIndex = Int((point.y - metrics.gridRect.minY) / unit)
        guard rowIndex >= 0, rowIndex < visibleRows else { return nil }

        let bandTop = metrics.gridRect.minY + CGFloat(rowIndex) * unit
        guard point.y <= bandTop + metrics.tileHeight else { return nil }
        return visibleRowValues[rowIndex]
    }

    // Nearest visible row for a y during a reorder drag — clamped so a drop
    // anywhere (including the gaps) still lands on a row.
    private func rowSlot(at y: CGFloat) -> Int? {
        let metrics = layoutMetrics()
        let unit = metrics.tileHeight + config.gap
        guard unit > 0 else { return nil }
        let index = Int(floor((y - metrics.gridRect.minY) / unit))
        return visibleRowValues[max(0, min(visibleRows - 1, index))]
    }

    func tileRect(for workspace: String) -> NSRect? {
        guard let row = workspaceRow(workspace),
              let col = workspaceColumn(workspace)
        else { return nil }

        guard let rowIndex = visibleRowValues.firstIndex(of: row),
              let colIndex = visibleColValues.firstIndex(of: col),
              isCellVisible(row: row, col: col)
        else { return nil }

        return tileRect(rowIndex: rowIndex, colIndex: colIndex, metrics: layoutMetrics())
    }

    private func workspace(at point: NSPoint) -> String? {
        let metrics = layoutMetrics()
        guard point.x >= metrics.gridRect.minX,
              point.y >= metrics.gridRect.minY
        else { return nil }

        let colIndex = Int((point.x - metrics.gridRect.minX) / (metrics.tileWidth + config.gap))
        let rowIndex = Int((point.y - metrics.gridRect.minY) / (metrics.tileHeight + config.gap))

        guard rowIndex >= 0, rowIndex < visibleRows,
              colIndex >= 0, colIndex < visibleCols
        else { return nil }

        let row = visibleRowValues[rowIndex]
        let col = visibleColValues[colIndex]
        guard isCellVisible(row: row, col: col) else { return nil }

        let rect = tileRect(rowIndex: rowIndex, colIndex: colIndex, metrics: metrics)
        guard rect.contains(point) else { return nil }

        return workspaceName(row: row, col: col)
    }

    private func canInsertWorkspace(
        around workspace: String,
        position: WorkspaceInsertionPosition
    ) -> Bool {
        guard let row = workspaceRow(workspace),
              let anchorColumn = workspaceColumn(workspace)
        else { return false }

        let insertionColumn = anchorColumn + (position == .after ? 1 : 0)
        guard 0..<workspaceCols ~= insertionColumn else { return false }

        let occupiedColumns = windowsByWorkspace.compactMap { candidate, windows -> Int? in
            guard !windows.isEmpty,
                  workspaceRow(candidate) == row
            else { return nil }
            return workspaceColumn(candidate)
        }
        let affectedColumns = occupiedColumns.filter { $0 >= insertionColumn }

        // Shifting a populated suffix needs one free slot on the right. With no
        // populated suffix, adding is useful only when it reveals a new edge cell.
        if affectedColumns.isEmpty {
            return !visibleColValues.contains(insertionColumn)
        }
        return (occupiedColumns.max() ?? insertionColumn) < workspaceCols - 1
    }

    func revealWorkspaceColumn(_ column: Int) {
        guard 0..<workspaceCols ~= column else { return }
        if !visibleColValues.contains(column) {
            visibleColValues.append(column)
            visibleColValues.sort()
        }
        gridOriginCol = visibleColValues.first ?? 0
        visibleCols = visibleColValues.count
        clearPlusButton()
        needsDisplay = true
    }

    // While dragging a window against the bottom edge, reveal one empty row of
    // tiles below it so the window can be dropped into a fresh project lane —
    // the drag-driven counterpart of the bottom "+" expansion. At most one row
    // is revealed per drag; mouseUp keeps it if used, collapses it otherwise.
    private func maybeRevealDropRow(at point: NSPoint) {
        guard !dragRevealedRow, canExpand(.bottom) else { return }
        let metrics = layoutMetrics()
        guard point.x >= metrics.gridRect.minX,
              point.y >= metrics.gridRect.maxY - dragRevealBand
        else { return }
        let before = visibleRowValues
        expand(.bottom)
        dragRevealedRow = visibleRowValues != before
    }

    private func collapseRevealedDropRow(_ row: Int?) {
        guard let row else { return }
        visibleRowValues.removeAll { $0 == row }
        if visibleRowValues.isEmpty { visibleRowValues = [1] }
        gridOriginRow = visibleRowValues.first ?? 1
        visibleRows = visibleRowValues.count
        needsDisplay = true
    }

    private struct WindowHit {
        let window: WorkspaceWindow
        let workspace: String
        let rect: NSRect
    }

    private func window(at point: NSPoint) -> WindowHit? {
        guard let workspace = workspace(at: point),
              let tile = tileRect(for: workspace)
        else { return nil }

        for (window, rect) in windowChipRects(workspace: workspace, tileRect: tile) {
            if rect.contains(point) {
                return WindowHit(window: window, workspace: workspace, rect: rect)
            }
        }

        // Overflow-strip icons are draggable/clickable too. Hand back a chip-
        // sized rect anchored at the icon so the drag preview looks like a chip.
        for (window, rect) in overflowIconRects(workspace: workspace, tileRect: tile)
        where rect.insetBy(dx: -2, dy: -3).contains(point) {
            let preview = NSRect(x: rect.minX, y: rect.midY - Style.rowHeight / 2,
                                 width: overflowChipSize(for: window).width, height: Style.rowHeight)
            return WindowHit(window: window, workspace: workspace, rect: preview)
        }
        return nil
    }

    // Icon rects for a tile's overflow strip (the hidden apps that fit). Single
    // source of truth shared by drawing and hover hit-testing.
    private func overflowIconRects(workspace: String, tileRect: NSRect) -> [(WorkspaceWindow, NSRect)] {
        let windows = windowsByWorkspace[workspace] ?? []
        let rows = windowChipRects(workspace: workspace, tileRect: tileRect)
        guard windows.count > rows.count, let last = rows.last?.1 else { return [] }

        let iconSide: CGFloat = 14
        let iconGap: CGFloat = 5
        let stripY = last.maxY + Style.rowGap + (Style.rowHeight - iconSide) / 2
        let maxX = last.maxX - 2
        var x = last.minX + 2
        var result: [(WorkspaceWindow, NSRect)] = []
        for window in windows[rows.count...] {
            guard x + iconSide <= maxX else { break }
            result.append((window, NSRect(x: x, y: stripY, width: iconSide, height: iconSide)))
            x += iconSide + iconGap
        }
        return result
    }

    // The overflow-strip icon under the pointer, if any (hit area padded a touch
    // since the icons are small).
    private func overflowIcon(at point: NSPoint) -> (window: WorkspaceWindow, rect: NSRect)? {
        guard let ws = workspace(at: point), let tile = tileRect(for: ws) else { return nil }
        for (window, rect) in overflowIconRects(workspace: ws, tileRect: tile)
        where rect.insetBy(dx: -2, dy: -3).contains(point) {
            return (window, rect)
        }
        return nil
    }

    private func updateOverflowHover(at point: NSPoint) {
        let hit = overflowIcon(at: point)
        if hit?.window.windowID != hoveredOverflowIcon?.window.windowID {
            hoveredOverflowIcon = hit
            if hit != nil { startTooltipAnimation() } else { stopTooltipAnimation() }
            needsDisplay = true
        }
    }

    // Content size of an overflow tooltip: a full window chip (icon + app name +
    // dim title), measured so nothing truncates.
    private func overflowChipSize(for window: WorkspaceWindow) -> NSSize {
        let appFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let label = NSMutableAttributedString(string: displayAppName(window.appName), attributes: [.font: appFont])
        let title = chipTitle(for: window)
        if !title.isEmpty {
            label.append(NSAttributedString(string: "  " + title, attributes: [.font: titleFont]))
        }
        let iconSide: CGFloat = 16
        let labelWidth = ceil(label.size().width)
        let width = min(380, 2 + iconSide + 7 + labelWidth + 6)
        return NSSize(width: width, height: Style.rowHeight)
    }

    // Floating chip naming the hovered overflow icon — same icon + name + title
    // a visible tile chip shows. Fade/rise is applied by the caller in draw().
    private func drawOverflowTooltip(_ window: WorkspaceWindow, near iconRect: NSRect) {
        let inner = overflowChipSize(for: window)
        let padX: CGFloat = 6, padY: CGFloat = 5
        let w = inner.width + padX * 2
        let h = inner.height + padY * 2

        // Flipped view: place above the icon (smaller y); drop below if clipped.
        var x = iconRect.midX - w / 2
        var y = iconRect.minY - h - 6
        if y < config.margin { y = iconRect.maxY + 6 }
        x = max(config.margin, min(x, bounds.maxX - config.margin - w))
        let box = NSRect(x: x, y: y, width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(increaseContrast ? 0.46 : 0.28)
        shadow.shadowBlurRadius = increaseContrast ? 8 : 16
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(reduceTransparency ? 1 : 0.94).setFill()
        NSBezierPath(roundedRect: box, xRadius: Style.chipRadius + 2, yRadius: Style.chipRadius + 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        tileBorderColor.setStroke()
        let border = NSBezierPath(
            roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Style.chipRadius + 2,
            yRadius: Style.chipRadius + 2
        )
        border.lineWidth = 1
        border.stroke()

        let chipRect = NSRect(x: box.minX + padX, y: box.minY + padY, width: inner.width, height: inner.height)
        drawWindowChip(window, in: chipRect, isFloating: false, isSourceGhost: false)
    }

    // Drive the tooltip's fade-in/rise. A 60 Hz timer eases progress 0→1 over a
    // short window, redrawing each tick; added to .common so it ticks during
    // pointer tracking.
    private func startTooltipAnimation() {
        tooltipTimer?.invalidate()
        if reduceMotion {
            tooltipProgress = 1
            needsDisplay = true
            return
        }
        tooltipProgress = 0
        let start = Date()
        let duration = 0.14
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let p = min(1.0, Date().timeIntervalSince(start) / duration)
            self.tooltipProgress = CGFloat(1 - pow(1 - p, 2))   // ease-out
            self.needsDisplay = true
            if p >= 1.0 { t.invalidate(); self.tooltipTimer = nil }
        }
        RunLoop.current.add(timer, forMode: .common)
        tooltipTimer = timer
    }

    private func stopTooltipAnimation() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        tooltipProgress = 0
    }

    private func drawHeader(in rect: NSRect) {
        let row = workspaceRow(focusedWorkspace).map(String.init) ?? ""
        let col = workspaceColumn(focusedWorkspace).map(String.init) ?? ""
        let text = config.headerText
            .replacingOccurrences(of: "{workspace}", with: focusedWorkspace)
            .replacingOccurrences(of: "{row}", with: row)
            .replacingOccurrences(of: "{col}", with: col)
        text.draw(
            in: NSRect(x: rect.minX + 1, y: rect.minY + 3, width: rect.width, height: 24),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: config.headerFontSize, weight: .bold),
                .foregroundColor: config.headerTextColor,
            ]
        )
    }

    private func drawTile(workspace: String, rect: NSRect) {
        let windows = windowsByWorkspace[workspace] ?? []
        let isFocused = workspace == focusedWorkspace
        let isDropTarget = draggedWindow != nil && didDrag && dragTargetWorkspace == workspace

        let path = NSBezierPath(roundedRect: rect, xRadius: tileRadius, yRadius: tileRadius)
        tileFill(empty: windows.isEmpty).setFill()
        path.fill()
        if isFocused {
            selectionFill.setFill()
            path.fill()
        } else if isDropTarget {
            selectionFill.withAlphaComponent(0.28).setFill()
            path.fill()
        }

        tileBorderColor.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: tileRadius, yRadius: tileRadius)
        border.lineWidth = increaseContrast ? max(1.5, config.missionTileBorderWidth) : config.missionTileBorderWidth
        border.stroke()

        drawWorkspaceLabel(workspace, windows: windows, in: rect)

        if isFocused || isDropTarget {
            selectionBorder.setStroke()
            let ringWidth: CGFloat = increaseContrast ? 3.5 : (isDropTarget ? 2.5 : 2)
            let ring = NSBezierPath(
                roundedRect: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2),
                xRadius: max(0, tileRadius - 0.5),
                yRadius: max(0, tileRadius - 0.5)
            )
            ring.lineWidth = ringWidth
            ring.stroke()
        }
    }

    private func drawWorkspaceLabel(_ workspace: String, windows: [WorkspaceWindow], in rect: NSRect) {
        guard !windows.isEmpty else { return }

        let rows = windowChipRects(workspace: workspace, tileRect: rect)
        for (window, rowRect) in rows {
            let isDraggedSource = didDrag && draggedWindow?.windowID == window.windowID
            drawWindowChip(window, in: rowRect, isFloating: false, isSourceGhost: isDraggedSource)
        }

        // Overflow: a compact strip of the hidden apps' icons (denser and more
        // informative than "+N more" text). Hover an icon for its app name.
        if windows.count > rows.count, let last = rows.last?.1 {
            let icons = overflowIconRects(workspace: workspace, tileRect: rect)
            for (window, iconRect) in icons {
                if let icon = appIcon(bundleID: window.bundleID) {
                    icon.draw(
                        in: iconRect,
                        from: .zero, operation: .sourceOver, fraction: 0.9,
                        respectFlipped: true, hints: nil
                    )
                }
            }

            // Any icons that didn't fit collapse into a trailing "+N".
            let remaining = (windows.count - rows.count) - icons.count
            let tx = (icons.last?.1.maxX ?? last.minX) + 5
            if remaining > 0, tx + 24 <= last.maxX {
                "+\(remaining)".draw(
                    in: NSRect(x: tx, y: last.maxY + Style.rowGap + (Style.rowHeight - 13) / 2, width: 28, height: 13),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: secondaryTextColor,
                    ]
                )
            }
        }
    }

    private func windowChipRects(workspace: String, tileRect: NSRect) -> [(WorkspaceWindow, NSRect)] {
        let windows = windowsByWorkspace[workspace] ?? []
        guard !windows.isEmpty else { return [] }

        let x = tileRect.minX + Style.pad
        let width = max(0, tileRect.width - Style.pad * 2)
        let regionTop = tileRect.minY + Style.pad
        let regionBottom = tileRect.maxY - Style.pad
        let unit = Style.rowHeight + Style.rowGap
        let capacity = max(1, Int((regionBottom - regionTop + Style.rowGap) / unit))
        let shown = windows.count > capacity ? max(1, capacity - 1) : windows.count

        // Center the content block (rows + a trailing overflow-strip band when
        // some windows spill over) in the tile so a sparse workspace doesn't
        // cluster its rows at the top with dead space below.
        let hasOverflow = windows.count > shown
        let contentHeight = CGFloat(shown) * Style.rowHeight
            + CGFloat(max(0, shown - 1)) * Style.rowGap
            + (hasOverflow ? unit : 0)
        let top = regionTop + max(0, (regionBottom - regionTop - contentHeight) / 2)

        return windows.prefix(shown).enumerated().map { index, window in
            let y = top + CGFloat(index) * unit
            return (window, NSRect(x: x, y: y, width: width, height: Style.rowHeight))
        }
    }

    // Window title with the app's own trailing " — AppName" suffix stripped,
    // so a duplicate app reads "Ghostty  bastion" not "Ghostty  ... - Ghostty".
    private func chipTitle(for window: WorkspaceWindow) -> String {
        var title = window.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" — ", " – ", " - "] {
            let suffix = separator + window.appName
            if title.hasSuffix(suffix) {
                title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return title == window.appName ? "" : title
    }

    private func drawWindowChip(
        _ window: WorkspaceWindow,
        in rect: NSRect,
        isFloating: Bool,
        isSourceGhost: Bool
    ) {
        NSGraphicsContext.saveGraphicsState()
        if isSourceGhost {
            NSGraphicsContext.current?.cgContext.setAlpha(0.3)
        }

        // Content rows stay visually quiet on the glass plane. Hover lifts a
        // row with a thin semantic fill; dragging uses restrained accent tint.
        let isHovered = !isFloating && hoveredWindowID == window.windowID
        let usesDarkSurface = isFloating || window.workspace == focusedWorkspace
        if isFloating || isHovered {
            let card = NSBezierPath(roundedRect: rect, xRadius: Style.chipRadius, yRadius: Style.chipRadius)
            if isFloating {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.shadowColor.withAlphaComponent(0.32)
                shadow.shadowBlurRadius = 14
                shadow.shadowOffset = NSSize(width: 0, height: -4)
                shadow.set()
                selectionFill.setFill()
                card.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                (usesDarkSurface ? selectionText.withAlphaComponent(0.09) : config.missionHoverColor).setFill()
                card.fill()
            }

            if isFloating {
                selectionBorder.setStroke()
                card.lineWidth = 1
                card.stroke()
            }
        }

        let iconSide = min(rect.height - 4, 19)
        var textX = rect.minX + (isFloating ? 6 : 2)
        if let icon = appIcon(bundleID: window.bundleID) {
            let iconRect = NSRect(x: textX, y: rect.minY + (rect.height - iconSide) / 2, width: iconSide, height: iconSide)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            textX = iconRect.maxX + 7
        }

        let name = displayAppName(window.appName)
        let label = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: usesDarkSurface ? selectionText : primaryTextColor,
            ]
        )
        let title = chipTitle(for: window)
        if !title.isEmpty {
            label.append(NSAttributedString(
                string: name.isEmpty ? title : "  " + title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: usesDarkSurface ? selectionSecondaryText : secondaryTextColor,
                ]
            ))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        label.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: label.length))
        let textRect = NSRect(x: textX, y: rect.minY + (rect.height - 14) / 2, width: max(0, rect.maxX - textX - 4), height: 14)
        label.draw(in: textRect)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawDraggedWindow() {
        guard didDrag,
              let draggedWindow,
              let point = draggedWindowPoint,
              draggedWindowSize.width > 0,
              draggedWindowSize.height > 0
        else { return }

        let rect = NSRect(
            x: point.x - draggedWindowOffset.x,
            y: point.y - draggedWindowOffset.y,
            width: draggedWindowSize.width,
            height: draggedWindowSize.height
        )
        drawWindowChip(draggedWindow, in: rect, isFloating: true, isSourceGhost: false)
    }

    // During a row reorder: dim the lifted lane and draw an accent insertion
    // line at the slot boundary where it would drop.
    private func drawRowDrag(metrics: LayoutMetrics) {
        guard didDrag, let draggedRow, let target = rowDragTarget else { return }
        guard let sourceIndex = visibleRowValues.firstIndex(of: draggedRow),
              let targetIndex = visibleRowValues.firstIndex(of: target)
        else { return }

        let unit = metrics.tileHeight + config.gap

        // Mark the lifted lane.
        let sourceY = metrics.gridRect.minY + CGFloat(sourceIndex) * unit
        let sourceBand = NSRect(x: config.margin, y: sourceY, width: bounds.width - config.margin * 2, height: metrics.tileHeight)
        selectionFill.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: sourceBand, xRadius: tileRadius, yRadius: tileRadius).fill()

        // Insertion line: above the target when moving up, below when moving down.
        let boundaryIndex = targetIndex <= sourceIndex ? targetIndex : targetIndex + 1
        let lineY = metrics.gridRect.minY + CGFloat(boundaryIndex) * unit - config.gap / 2
        let line = NSBezierPath()
        line.move(to: NSPoint(x: config.margin, y: lineY))
        line.line(to: NSPoint(x: metrics.gridRect.maxX, y: lineY))
        line.lineWidth = 2.5
        selectionBorder.setStroke()
        line.stroke()
    }

    // Project-lane names stay plain and vertical: no number, pill, or placeholder
    // chrome. Weight alone distinguishes the focused lane.
    private func drawRowName(_ name: String, row: Int, in rect: NSRect) {
        let focused = workspaceRow(focusedWorkspace) == row
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: focused ? .semibold : .medium),
            .foregroundColor: config.missionRowTextColor,
        ]
        let label = name as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var imageAttributes = attributes
        imageAttributes[.paragraphStyle] = paragraph

        let naturalSize = label.size(withAttributes: attributes)
        let width = ceil(min(naturalSize.width, max(8, rect.height - 10)))
        let height = ceil(naturalSize.height)
        guard width > 0, height > 0 else { return }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        label.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            withAttributes: imageAttributes
        )
        image.unlockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -.pi / 2)
        image.draw(
            in: NSRect(x: -width / 2, y: -height / 2, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        context.restoreGState()
    }

    // Overlay an editable field on the row band and focus it. The mission panel
    // is a nonactivating key-capable panel, so typing works without stealing
    // foreground app activation.
    func beginRenaming(row: Int) {
        teardownEditor()

        guard let rowIndex = visibleRowValues.firstIndex(of: row) else { return }
        let metrics = layoutMetrics()
        let bandTop = metrics.gridRect.minY + CGFloat(rowIndex) * (metrics.tileHeight + config.gap)
        let height: CGFloat = 22
        let width = min(220, bounds.width - config.margin * 2)
        let rect = NSRect(
            x: config.margin,
            y: bandTop + (metrics.tileHeight - height) / 2,
            width: width,
            height: height
        )

        let field = NSTextField(frame: rect)
        field.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        field.stringValue = displayRowName(row)
        field.placeholderString = defaultRowName(row)
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        addSubview(field)

        rowEditor = field
        editingRow = row

        // Defer focus past the current mouse-down so the field keeps it.
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.rowEditor === field else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
    }

    // Commit any in-progress rename (Enter, click-away, or panel hide).
    func finishEditing() {
        guard rowEditor != nil else { return }
        commitEditing()
    }

    private func commitEditing() {
        guard let editor = rowEditor, let row = editingRow else { return }
        let value = editor.stringValue
        teardownEditor()
        onRowNameCommitted?(row, value)
    }

    private func cancelEditing() {
        teardownEditor()
    }

    private func teardownEditor() {
        guard let editor = rowEditor else { return }
        rowEditor = nil
        editingRow = nil
        editor.delegate = nil
        if window?.firstResponder === editor || window?.firstResponder === editor.currentEditor() {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
        needsDisplay = true
    }

    private func rightAlignedParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }

}

extension MissionControlView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Reached on focus loss (e.g. clicking another app). Enter/Esc already
        // tore the editor down, so this guard makes the commit idempotent.
        finishEditing()
    }
}

// Borderless panels can't become key by default; this lets the inline rename
// field receive keystrokes without activating the foreground app.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: HudConfig
    private let aerospace = AeroSpaceClient()
    private lazy var view = HudView(frame: NSRect(x: 0, y: 0, width: 650, height: 445), config: config)
    private lazy var missionView: MissionControlView = {
        var missionConfig = config
        missionConfig.headerHeight = 0
        return MissionControlView(frame: NSRect(x: 0, y: 0, width: 1000, height: 620), config: missionConfig)
    }()
    private var panel: NSPanel?
    private var missionPanel: NSPanel?
    private var missionGlassView: NSGlassEffectView?
    private var stateTimer: Timer?
    private var focusedTimer: Timer?
    private var windowsTimer: Timer?
    private var configTimer: Timer?
    private var lastConfigModificationDate: Date?
    private var hideTimer: Timer?
    private var focusedPollInFlight = false
    private var windowsPollInFlight = false
    private var pointerInsideHud = false
    private var suppressFrameSave = false
    private var suppressMissionFrameSave = false
    private let missionFrameKey = "AeroSpaceMissionFrame"
    private let rowNamesKey = "AeroSpaceRowNames"
    private var missionClickMonitor: Any?
    private var lastShowSignal = ""
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private var aeroSpaceResponsive = true

    override init() {
        self.config = HudConfig.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createMissionPanel()
        view.onWorkspaceClick = { [weak self] workspace in
            self?.jump(to: workspace)
        }
        missionView.onWorkspaceClick = { [weak self] workspace in
            self?.jump(to: workspace)
            self?.hideMissionControl()
        }
        missionView.onWindowClick = { [weak self] window in
            guard let self else { return }
            // Dismiss first so Mission Control's key-panel teardown cannot
            // restore the previously active app after AeroSpace focuses this
            // window. Finder is especially prone to losing that race.
            self.hideMissionControl()
            self.focus(window: window)
        }
        missionView.onWindowMove = { [weak self] window, workspace in
            self?.move(window: window, to: workspace)
        }
        missionView.onInsertWorkspace = { [weak self] workspace, position in
            self?.insertWorkspaceGap(around: workspace, position: position)
        }
        missionView.onReloadConfig = { [weak self] in
            self?.reloadConfig()
        }
        missionView.onResetSize = { [weak self] in
            self?.resetMissionSize()
        }
        missionView.rowNames = loadRowNames()
        missionView.onRowNameCommitted = { [weak self] row, rawName in
            self?.commitRowName(row, rawName)
        }
        missionView.onReorderRows = { [weak self] from, to in
            self?.reorderRows(from: from, to: to)
        }
        missionView.onKeyboardWorkspaceNavigate = { [weak self] workspace in
            self?.jump(to: workspace, showMiniHud: false, refocusMissionControl: true)
        }
        missionView.onKeyboardDismiss = { [weak self] in
            self?.hideMissionControl()
        }
        view.onResetSize = { [weak self] in
            self?.resetMiniHudSize()
        }
        view.onInteractionStart = { [weak self] in
            self?.cancelHideTimer()
        }
        view.onInteractionEnd = { [weak self] in
            self?.scheduleHide()
        }
        view.onPointerEnter = { [weak self] in
            self?.pointerInsideHud = true
            self?.cancelHideTimer()
        }
        view.onPointerExit = { [weak self] in
            self?.pointerInsideHud = false
            self?.scheduleHide()
        }
        view.onReloadConfig = { [weak self] in
            self?.reloadConfig()
        }
        pollStateHint()
        pollFocusedWorkspace()
        pollWindows()
        scheduleHide()

        stateTimer = Timer.scheduledTimer(withTimeInterval: statePollInterval, repeats: true) { [weak self] _ in
            self?.pollStateHint()
        }
        focusedTimer = Timer.scheduledTimer(withTimeInterval: focusedPollInterval, repeats: true) { [weak self] _ in
            self?.pollFocusedWorkspace()
        }
        windowsTimer = Timer.scheduledTimer(withTimeInterval: windowsPollInterval, repeats: true) { [weak self] _ in
            self?.pollWindows()
        }
        lastConfigModificationDate = HudConfig.modificationDate()
        configTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.pollConfigFile()
        }

        setupStatusItem()
    }

    private func createPanel() {
        let frame = validSavedFrame() ?? defaultFrame()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = config.opacity
        panel.hasShadow = config.shadowEnabled
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = view
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        self.panel = panel
    }

    private func createMissionPanel() {
        let panel = KeyablePanel(
            contentRect: missionControlFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = config.missionPanelOpacity
        // NSGlassEffectView supplies its own material depth. NSWindow's legacy
        // rectangular shadow leaks through rounded corners, so keep it disabled.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Clear Liquid Glass exposes lensing/refraction instead of reading as a
        // conventional blur. Native dark tint adds separation without covering
        // underlying content or stacking another material layer.
        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]

        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        configureMissionGlass(glass)

        missionView.frame = container.bounds
        missionView.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        container.addSubview(missionView)

        panel.contentView = container
        panel.orderOut(nil)

        // Persist user move/resize so a hand-tuned size survives toggling.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(missionFrameChanged(_:)),
                name: name,
                object: panel
            )
        }

        self.missionGlassView = glass
        self.missionPanel = panel
    }

    private func configureMissionGlass(_ glass: NSGlassEffectView) {
        glass.style = config.missionGlassStyle == "regular" ? .regular : .clear
        glass.cornerRadius = config.missionGlassCornerRadius
        glass.tintColor = config.missionGlassTintColor.withAlphaComponent(config.missionGlassTintOpacity)
        glass.clipsToBounds = true
    }

    @objc private func missionFrameChanged(_ notification: Notification) {
        guard !suppressMissionFrameSave, let missionPanel else { return }
        guard (notification.object as? NSWindow) === missionPanel else { return }
        UserDefaults.standard.set(NSStringFromRect(missionPanel.frame), forKey: missionFrameKey)
    }

    private func savedMissionFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: missionFrameKey) else { return nil }
        let frame = NSRectFromString(string)
        guard frame.width >= 320, frame.height >= 200 else { return nil }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? frame : nil
    }

    private func resetMissionSize() {
        UserDefaults.standard.removeObject(forKey: missionFrameKey)
        guard let missionPanel, missionPanel.isVisible else { return }
        let grid = missionControlGrid()
        suppressMissionFrameSave = true
        missionPanel.setFrame(missionControlFrame(rows: grid.rows.count, cols: grid.cols.count), display: true)
        suppressMissionFrameSave = false
    }

    private func loadRowNames() -> [Int: String] {
        guard let stored = UserDefaults.standard.dictionary(forKey: rowNamesKey) as? [String: String] else {
            return [:]
        }
        var result: [Int: String] = [:]
        for (key, value) in stored {
            if let row = Int(key), !value.isEmpty { result[row] = value }
        }
        return result
    }

    private func saveRowNames(_ names: [Int: String]) {
        var stored: [String: String] = [:]
        for (row, value) in names { stored[String(row)] = value }
        UserDefaults.standard.set(stored, forKey: rowNamesKey)
    }

    // Persist an inline-edited project-lane name. An empty value (or the default)
    // clears the override so the row falls back to "base"/"wNx".
    private func commitRowName(_ row: Int, _ rawName: String) {
        let fallback = defaultRowName(row)
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = missionView.rowNames
        if name.isEmpty || name == fallback {
            names.removeValue(forKey: row)
        } else {
            names[row] = name
        }
        missionView.rowNames = names
        saveRowNames(names)
    }

    // Drag-reorder a project lane: lane `sourceRow` moves into `targetRow`'s
    // visible slot, and each visible lane's windows + custom name travel with
    // it. Sparse inactive rows stay hidden and untouched.
    private func reorderRows(from sourceRow: Int, to targetRow: Int) {
        let slots = missionView.visibleRowValues
        guard slots.contains(sourceRow), slots.contains(targetRow), sourceRow != targetRow else { return }

        // Reinsert the source row at the target position to get the new lane order.
        var sequence = slots
        guard let fromIndex = sequence.firstIndex(of: sourceRow),
              let toIndex = sequence.firstIndex(of: targetRow)
        else { return }
        sequence.insert(sequence.remove(at: fromIndex), at: toIndex)

        // destinationRow[r] = visible row slot the lane currently at row r ends up in.
        var destinationRow: [Int: Int] = [:]
        for (offset, source) in sequence.enumerated() {
            destinationRow[source] = slots[offset]
        }
        guard slots.contains(where: { destinationRow[$0] != $0 }) else { return }

        // Names: only explicit overrides travel; defaults stay positional.
        let originalNames = missionView.rowNames
        var newNames = originalNames
        for row in slots { newNames.removeValue(forKey: row) }
        for row in slots {
            if let name = originalNames[row], let destination = destinationRow[row] {
                newNames[destination] = name
            }
        }
        missionView.rowNames = newNames
        saveRowNames(newNames)

        // Windows: remap every window to the same column in its lane's new row.
        let snapshot = view.windowsByWorkspace
        var optimistic: [String: [WorkspaceWindow]] = [:]
        var moves: [(WorkspaceWindow, String)] = []
        for (workspace, windows) in snapshot {
            guard let row = workspaceRow(workspace),
                  let column = workspaceColumn(workspace),
                  let destination = destinationRow[row], destination != row
            else {
                optimistic[workspace, default: []].append(contentsOf: windows)
                continue
            }
            let target = workspaceName(row: destination, col: column)
            for window in windows {
                let moved = window.moved(to: target)
                optimistic[target, default: []].append(moved)
                moves.append((window, target))
            }
        }
        for workspace in optimistic.keys {
            optimistic[workspace] = optimistic[workspace]?.sorted {
                if $0.appName == $1.appName { return $0.windowID < $1.windowID }
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
        }

        view.windowsByWorkspace = optimistic
        missionView.windowsByWorkspace = optimistic
        _ = updateVisibleGrid()

        guard !moves.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = moves.allSatisfy { self.aerospace.moveWindow($0.0, to: $0.1) }

            DispatchQueue.main.async {
                if !ok {
                    self.view.windowsByWorkspace = snapshot
                    self.missionView.windowsByWorkspace = snapshot
                    self.missionView.rowNames = originalNames
                    self.saveRowNames(originalNames)
                    _ = self.updateVisibleGrid()
                }
                self.pollWindows()
            }
        }
    }

    // Insert an empty workspace slot inside one project lane. AeroSpace has no
    // persistent empty-workspace object, so every populated workspace at the
    // insertion column and to its right moves one column. That leaves a stable
    // interior gap while keeping all other project lanes untouched.
    private func insertWorkspaceGap(
        around anchorWorkspace: String,
        position: WorkspaceInsertionPosition
    ) {
        guard let row = workspaceRow(anchorWorkspace),
              let anchorColumn = workspaceColumn(anchorWorkspace)
        else { return }

        let insertionColumn = anchorColumn + (position == .after ? 1 : 0)
        guard 0..<workspaceCols ~= insertionColumn else { return }

        let snapshot = view.windowsByWorkspace
        let affectedColumns = snapshot.compactMap { workspace, windows -> Int? in
            guard !windows.isEmpty,
                  workspaceRow(workspace) == row,
                  let column = workspaceColumn(workspace),
                  column >= insertionColumn
            else { return nil }
            return column
        }

        // No populated suffix means no remap is needed. Reveal one transient
        // edge cell, matching the existing edge-plus behavior.
        guard let lastOccupiedColumn = affectedColumns.max() else {
            missionView.revealWorkspaceColumn(insertionColumn)
            return
        }
        guard lastOccupiedColumn < workspaceCols - 1 else {
            NSSound.beep()
            return
        }

        var optimistic: [String: [WorkspaceWindow]] = [:]
        var moves: [(window: WorkspaceWindow, target: String)] = []
        for (workspace, windows) in snapshot {
            guard workspaceRow(workspace) == row,
                  let column = workspaceColumn(workspace),
                  column >= insertionColumn
            else {
                optimistic[workspace, default: []].append(contentsOf: windows)
                continue
            }

            let target = workspaceName(row: row, col: column + 1)
            for window in windows {
                optimistic[target, default: []].append(window.moved(to: target))
                moves.append((window, target))
            }
        }
        for workspace in optimistic.keys {
            optimistic[workspace] = optimistic[workspace]?.sorted {
                if $0.appName == $1.appName { return $0.windowID < $1.windowID }
                return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
            }
        }

        // Move rightmost workspaces first so destinations are vacated before
        // their left-hand neighbors arrive.
        moves.sort {
            let leftColumn = workspaceColumn($0.window.workspace) ?? 0
            let rightColumn = workspaceColumn($1.window.workspace) ?? 0
            if leftColumn != rightColumn { return leftColumn > rightColumn }
            return $0.window.windowID < $1.window.windowID
        }

        let originalFocusedWorkspace = view.focusedWorkspace
        var shiftedFocusedWorkspace = originalFocusedWorkspace
        if snapshot[originalFocusedWorkspace]?.isEmpty == false,
           workspaceRow(originalFocusedWorkspace) == row,
           let focusedColumn = workspaceColumn(originalFocusedWorkspace),
           focusedColumn >= insertionColumn
        {
            shiftedFocusedWorkspace = workspaceName(row: row, col: focusedColumn + 1)
        }

        view.windowsByWorkspace = optimistic
        missionView.windowsByWorkspace = optimistic
        setFocusedWorkspace(shiftedFocusedWorkspace, showMiniHud: false)
        let optimisticGrid = missionControlGrid()
        missionView.setGrid(rows: optimisticGrid.rows, cols: optimisticGrid.cols)
        missionView.revealWorkspaceColumn(insertionColumn)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var completed: [(window: WorkspaceWindow, target: String)] = []
            var succeeded = true
            for move in moves {
                if self.aerospace.moveWindow(move.window, to: move.target) {
                    completed.append(move)
                } else {
                    succeeded = false
                    break
                }
            }

            // Best-effort rollback keeps partially completed suffix moves from
            // leaving user windows merged into destination workspaces.
            if !succeeded {
                for move in completed.reversed() {
                    _ = self.aerospace.moveWindow(move.window, to: move.window.workspace)
                }
            } else if shiftedFocusedWorkspace != originalFocusedWorkspace {
                self.aerospace.switchWorkspace(shiftedFocusedWorkspace)
            }

            DispatchQueue.main.async {
                if succeeded {
                    if shiftedFocusedWorkspace != originalFocusedWorkspace {
                        self.setFocusedWorkspace(shiftedFocusedWorkspace, showMiniHud: false)
                        self.writeFocusedState(shiftedFocusedWorkspace)
                    }
                } else {
                    self.view.windowsByWorkspace = snapshot
                    self.missionView.windowsByWorkspace = snapshot
                    self.setFocusedWorkspace(originalFocusedWorkspace, showMiniHud: false)
                    let restoredGrid = self.missionControlGrid()
                    self.missionView.setGrid(rows: restoredGrid.rows, cols: restoredGrid.cols)
                }
                self.pollWindows()
            }
        }
    }

    private func resetMiniHudSize() {
        UserDefaults.standard.removeObject(forKey: "AeroSpaceHudFrame")
        guard let panel else { return }
        suppressFrameSave = true
        panel.setFrame(defaultFrame(), display: true)
        suppressFrameSave = false
    }

    // Mission Control spans the active rows and columns. A row or column is
    // active when at least one app exists anywhere in it; the visible span is
    // the contiguous range from the first to the last active row/column, so an
    // empty workspace wedged between two active ones keeps its slot instead of
    // collapsing and sliding its neighbors together.
    private func missionControlGrid() -> (rows: [Int], cols: [Int]) {
        var rowSet = Set<Int>()
        var colSet = Set<Int>()

        for (workspace, windows) in view.windowsByWorkspace {
            guard !windows.isEmpty else { continue }
            if let row = workspaceRow(workspace) { rowSet.insert(row) }
            if let col = workspaceColumn(workspace) { colSet.insert(col) }
        }

        if rowSet.isEmpty, let row = workspaceRow(view.focusedWorkspace) { rowSet.insert(row) }
        if colSet.isEmpty, let col = workspaceColumn(view.focusedWorkspace) { colSet.insert(col) }
        if rowSet.isEmpty { rowSet.insert(1) }
        if colSet.isEmpty { colSet.insert(0) }

        let rows = Array(rowSet.min()!...rowSet.max()!)
        let cols = Array(colSet.min()!...colSet.max()!)
        return (rows, cols)
    }

    private func missionControlFrame() -> NSRect {
        let grid = missionControlGrid()
        return missionControlFrame(rows: grid.rows.count, cols: grid.cols.count)
    }

    // Centered panel sized to the active grid: tiles mirror the screen
    // aspect ratio and grow to fill up to 72% of the screen.
    private func missionControlFrame(rows: Int, cols: Int) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = min(screen.width * 0.72, screen.width - config.screenPadding * 2)
        let maxHeight = min(screen.height * 0.72, screen.height - config.screenPadding * 2)

        let colCount = CGFloat(max(1, cols))
        let rowCount = CGFloat(max(1, rows))
        let tileAspect = screen.height / screen.width

        let chromeWidth = config.margin * 2 + MissionControlView.Style.railWidth + config.gap * (colCount - 1)
        let chromeHeight = config.margin * 2 + config.headerHeight + config.gap * (rowCount - 1)

        let tileWidthForWidth = (maxWidth - chromeWidth) / colCount
        let tileWidthForHeight = ((maxHeight - chromeHeight) / rowCount) / tileAspect
        let tileWidth = max(1, min(tileWidthForWidth, tileWidthForHeight))
        let tileHeight = tileWidth * tileAspect

        let width = tileWidth * colCount + chromeWidth
        let height = tileHeight * rowCount + chromeHeight

        return NSRect(
            x: screen.midX - width / 2,
            y: screen.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: view.preferredWidth(for: view.visibleCols),
            height: view.preferredHeight(for: view.visibleRows)
        )
        return NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }

    private func validSavedFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: "AeroSpaceHudFrame") else { return nil }
        let frame = NSRectFromString(string)
        guard frame.width >= config.minimumWidth, frame.height >= 80 else { return nil }

        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(frame) {
                return frame
            }
        }
        return nil
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        guard !suppressFrameSave else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "AeroSpaceHudFrame")
    }

    private func pollStateHint() {
        guard let hint = try? String(contentsOfFile: focusedStatePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            hint.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil
        else {
            pollShowSignal()
            return
        }

        setFocusedWorkspace(hint)
        pollShowSignal()
    }

    private func pollShowSignal() {
        guard let signal = try? String(contentsOfFile: missionControlSignalPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !signal.isEmpty,
            signal != lastShowSignal
        else { return }

        lastShowSignal = signal

        if let workspace = signal
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first(where: { $0.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil })
        {
            setFocusedWorkspace(workspace)
            writeFocusedState(workspace)
        }

        pollWindows()
        toggleMissionControl()
    }

    private func pollFocusedWorkspace() {
        guard !focusedPollInFlight else { return }
        focusedPollInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let focused = self.aerospace.focusedWorkspace()

            DispatchQueue.main.async {
                self.aeroSpaceResponsive = focused != nil
                if let focused {
                    self.setFocusedWorkspace(focused)
                    self.writeFocusedState(focused)
                }
                self.focusedPollInFlight = false
            }
        }
    }

    private func pollWindows() {
        guard !windowsPollInFlight else { return }
        windowsPollInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let windows = self.aerospace.windowsByWorkspace()

            DispatchQueue.main.async {
                // Reveal only on a structural change (window added/removed/moved
                // between workspaces, or app set changed) — NOT on bare title
                // churn. Window titles update constantly with no user action
                // (terminal cwd, browser tab, music track, unread counts), and
                // since `WorkspaceWindow` equality folds in `windowTitle`, a raw
                // `!=` here flashed the HUD every 3s poll. The mini HUD renders
                // app-name sets, never titles, so title diffs are pure noise.
                let layoutChanged = self.layoutSignature(self.view.windowsByWorkspace) != self.layoutSignature(windows)
                self.view.windowsByWorkspace = windows
                self.missionView.windowsByWorkspace = windows
                let gridChanged = self.updateVisibleGrid()
                if layoutChanged || gridChanged {
                    self.showPanelTemporarily()
                }
                self.windowsPollInFlight = false
            }
        }
    }

    // Title-independent fingerprint of the workspace layout: per workspace, the
    // sorted set of (windowID, appName). Two polls compare equal as long as the
    // same windows live in the same workspaces with the same apps — only their
    // titles moved. Used to gate HUD reveals so title churn stays silent.
    private func layoutSignature(_ map: [String: [WorkspaceWindow]]) -> [String: [String]] {
        var signature: [String: [String]] = [:]
        for (workspace, windows) in map {
            signature[workspace] = windows
                .map { "\($0.windowID)\u{1f}\($0.appName)" }
                .sorted()
        }
        return signature
    }

    private func setFocusedWorkspace(_ workspace: String, showMiniHud: Bool = true) {
        guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil else { return }

        let focusedChanged = view.focusedWorkspace != workspace
        view.focusedWorkspace = workspace
        missionView.focusedWorkspace = workspace
        let gridChanged = updateVisibleGrid()

        if showMiniHud && (focusedChanged || gridChanged) {
            showPanelTemporarily()
        }

    }

    private func writeFocusedState(_ workspace: String) {
        try? "\(workspace)\n".write(toFile: focusedStatePath, atomically: true, encoding: .utf8)
    }

    private func jump(to workspace: String, showMiniHud: Bool = true, refocusMissionControl: Bool = false) {
        setFocusedWorkspace(workspace, showMiniHud: showMiniHud)
        writeFocusedState(workspace)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.aerospace.switchWorkspace(workspace)
            guard refocusMissionControl else { return }

            DispatchQueue.main.async { [weak self] in
                self?.refocusMissionControlKeyboard()
                self?.refocusMissionControlKeyboard(after: 0.15)
            }
        }
    }

    private func focus(window: WorkspaceWindow) {
        setFocusedWorkspace(window.workspace)
        writeFocusedState(window.workspace)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.aerospace.focusWindow(window)
        }
    }

    private func move(window: WorkspaceWindow, to workspace: String) {
        guard workspace.range(of: #"^w[1-9][0-9]$"#, options: .regularExpression) != nil,
              workspace != window.workspace
        else { return }

        let previous = view.windowsByWorkspace
        view.windowsByWorkspace = windowsByMoving(window: window, to: workspace, in: previous)
        missionView.windowsByWorkspace = view.windowsByWorkspace
        let gridChanged = updateVisibleGrid()
        if gridChanged {
            showPanelTemporarily()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let moved = self.aerospace.moveWindow(window, to: workspace)

            DispatchQueue.main.async {
                if moved {
                    self.pollWindows()
                } else {
                    self.view.windowsByWorkspace = previous
                    self.missionView.windowsByWorkspace = previous
                    _ = self.updateVisibleGrid()
                    self.showPanelTemporarily()
                }
            }
        }
    }

    private func windowsByMoving(
        window: WorkspaceWindow,
        to workspace: String,
        in windowsByWorkspace: [String: [WorkspaceWindow]]
    ) -> [String: [WorkspaceWindow]] {
        var next = windowsByWorkspace

        for key in Array(next.keys) {
            next[key]?.removeAll { $0.windowID == window.windowID }
            if next[key]?.isEmpty == true {
                next.removeValue(forKey: key)
            }
        }

        next[workspace, default: []].append(window.moved(to: workspace))
        next[workspace]?.sort {
            if $0.appName == $1.appName {
                return $0.windowID < $1.windowID
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
        return next
    }

    private func pollConfigFile() {
        guard let modified = HudConfig.modificationDate() else { return }
        guard let previous = lastConfigModificationDate else {
            lastConfigModificationDate = modified
            return
        }
        guard modified != previous else { return }
        lastConfigModificationDate = modified
        reloadConfig(showMiniHud: false)
    }

    private func reloadConfig(showMiniHud: Bool = true) {
        config = HudConfig.load()
        lastConfigModificationDate = HudConfig.modificationDate()
        view.config = config
        missionView.config = config

        if let panel {
            panel.alphaValue = config.opacity
            panel.hasShadow = config.shadowEnabled
            resizePanel(rows: view.visibleRows, cols: view.visibleCols)
            if showMiniHud {
                panel.orderFrontRegardless()
            }
        }
        if let missionPanel {
            if let missionGlassView {
                configureMissionGlass(missionGlassView)
            }
            let grid = missionControlGrid()
            missionView.setGrid(rows: grid.rows, cols: grid.cols)
            let frame = savedMissionFrame() ?? missionControlFrame(rows: grid.rows.count, cols: grid.cols.count)
            suppressMissionFrameSave = true
            missionPanel.setFrame(frame, display: true)
            suppressMissionFrameSave = false
            missionPanel.alphaValue = config.missionPanelOpacity
            missionPanel.hasShadow = false
        }

        updateStatusItemVisibility()
        scheduleHide()
    }

    private func updateVisibleGrid() -> Bool {
        let focusedRow = workspaceRow(view.focusedWorkspace) ?? 1
        let appRow = view.windowsByWorkspace.keys.compactMap(workspaceRow).max() ?? 1
        let rows = min(workspaceRows, max(1, focusedRow, appRow))
        let focusedColumn = workspaceColumn(view.focusedWorkspace) ?? 0
        let appColumn = view.windowsByWorkspace.keys.compactMap(workspaceColumn).max() ?? 0
        let cols = min(workspaceCols, max(1, focusedColumn + 1, appColumn + 1))
        let changed = view.visibleRows != rows || view.visibleCols != cols

        view.visibleRows = rows
        view.visibleCols = cols
        resizePanel(rows: rows, cols: cols)
        return changed
    }

    private func resizePanel(rows rowCount: Int, cols colCount: Int) {
        guard let panel else { return }

        let current = panel.frame
        let newWidth = view.preferredWidth(for: colCount)
        let newHeight = view.preferredHeight(for: rowCount)
        guard abs(current.width - newWidth) > 0.5 || abs(current.height - newHeight) > 0.5 else { return }

        var next = current
        next.origin.x = current.maxX - newWidth
        next.origin.y = current.maxY - newHeight
        next.size.width = newWidth
        next.size.height = newHeight
        next = clampedToVisibleScreen(next)

        panel.setFrame(next, display: true)
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "AeroSpaceHudFrame")
    }

    private func clampedToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        else { return frame }

        let visible = screen.visibleFrame.insetBy(dx: config.screenPadding, dy: config.screenPadding)
        var next = frame

        if next.maxX > visible.maxX {
            next.origin.x = visible.maxX - next.width
        }
        if next.minX < visible.minX {
            next.origin.x = visible.minX
        }
        if next.maxY > visible.maxY {
            next.origin.y = visible.maxY - next.height
        }
        if next.minY < visible.minY {
            next.origin.y = visible.minY
        }

        return next
    }

    private func showPanelTemporarily() {
        panel?.orderFrontRegardless()
        scheduleHide()
    }

    private func toggleMissionControl() {
        guard let missionPanel else { return }

        if missionPanel.isVisible {
            hideMissionControl()
            return
        }

        missionView.focusedWorkspace = view.focusedWorkspace
        missionView.windowsByWorkspace = view.windowsByWorkspace
        let grid = missionControlGrid()
        missionView.setGrid(rows: grid.rows, cols: grid.cols)
        let frame = savedMissionFrame() ?? missionControlFrame(rows: grid.rows.count, cols: grid.cols.count)
        suppressMissionFrameSave = true
        missionPanel.setFrame(frame, display: true)
        suppressMissionFrameSave = false
        missionPanel.orderFrontRegardless()
        refocusMissionControlKeyboard()
        installMissionClickMonitor()
    }

    private func refocusMissionControlKeyboard(after delay: TimeInterval = 0) {
        if delay <= 0 {
            refocusMissionControlKeyboardNow()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refocusMissionControlKeyboardNow()
        }
    }

    private func refocusMissionControlKeyboardNow() {
        guard let missionPanel, missionPanel.isVisible else { return }
        missionPanel.orderFrontRegardless()
        missionPanel.makeKey()
        missionPanel.makeFirstResponder(missionView)
    }

    private func hideMissionControl() {
        missionView.finishEditing()
        removeMissionClickMonitor()
        missionPanel?.orderOut(nil)
    }

    // Dismiss Mission Control on any click outside its panel. Clicks inside the
    // panel are delivered locally, so a global mouse-down means "outside".
    private func installMissionClickMonitor() {
        guard missionClickMonitor == nil else { return }
        missionClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideMissionControl()
        }
    }

    private func removeMissionClickMonitor() {
        if let monitor = missionClickMonitor {
            NSEvent.removeMonitor(monitor)
            missionClickMonitor = nil
        }
    }

    private func scheduleHide() {
        guard autoHideEnabled else { return }
        guard !pointerInsideHud else {
            cancelHideTimer()
            return
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: config.autoHideDelay, repeats: false) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func hidePanel() {
        guard !pointerInsideHud else { return }
        panel?.orderOut(nil)
    }

    // MARK: Menu bar status item

    // A menu-bar item that signals at a glance whether the AeroSpace setup is
    // live — the HUD itself and AeroSpace responding — and exposes the common
    // actions. Accessory (LSUIElement) apps may own status items even with no
    // Dock tile.
    private func setupStatusItem() {
        guard config.showMenuBar, statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusIcon()

        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.refreshStatusIcon()
        }
    }

    private func updateStatusItemVisibility() {
        if config.showMenuBar {
            if statusItem == nil { setupStatusItem() } else { refreshStatusIcon() }
        } else if let item = statusItem {
            statusTimer?.invalidate()
            statusTimer = nil
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private struct SetupStatus {
        let aerospace: Bool
        let hud: Bool
        var allUp: Bool { aerospace && hud }
    }

    private func setupStatus() -> SetupStatus {
        SetupStatus(
            aerospace: aeroSpaceResponsive,
            hud: true
        )
    }

    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let healthy = setupStatus().allUp
        let symbol = healthy ? "square.grid.3x3.fill" : "exclamationmark.triangle.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [healthy ? .systemGreen : .systemOrange]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AeroSpace setup status")?
            .withSymbolConfiguration(configuration) {
            image.isTemplate = false
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = healthy ? "▦" : "⚠︎"
        }
    }

    // Rebuilt each time the menu opens so the component states are current.
    private func rebuildStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        let status = setupStatus()

        let title = NSMenuItem(
            title: status.allUp ? "AeroSpace setup: all running" : "AeroSpace setup: needs attention",
            action: nil, keyEquivalent: ""
        )
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(statusLine("AeroSpace", up: status.aerospace, upText: "running", downText: "not responding"))
        menu.addItem(statusLine("HUD", up: status.hud, upText: "running", downText: "stopped"))

        menu.addItem(.separator())
        menu.addItem(action("Open Mission Control", #selector(menuOpenMissionControl)))
        menu.addItem(action("Reload Config", #selector(menuReloadConfig)))
        menu.addItem(action("Reset HUD Size", #selector(menuResetSize)))
        menu.addItem(.separator())
        menu.addItem(action("Quit AeroSpace HUD", #selector(menuQuit)))
    }

    private func statusLine(_ name: String, up: Bool, upText: String, downText: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(name) — \(up ? upText : downText)", action: nil, keyEquivalent: "")
        let symbol = up ? "checkmark.circle.fill" : "xmark.circle.fill"
        let configuration = NSImage.SymbolConfiguration(paletteColors: [up ? .systemGreen : .systemRed])
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuOpenMissionControl() { toggleMissionControl() }
    @objc private func menuReloadConfig() { reloadConfig() }
    @objc private func menuResetSize() { resetMiniHudSize() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu()
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
