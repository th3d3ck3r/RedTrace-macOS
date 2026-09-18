import SwiftUI
import AppKit
import Darwin
import UniformTypeIdentifiers

private let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".redtrace/stream.log")

enum WindowMode: String, CaseIterable, Identifiable, Hashable {
    case watcher
    case runner
    case codex
    case btop
    case chat

    var id: String { rawValue }
}

enum MonitorTile: String, CaseIterable, Identifiable, Hashable {
    case cpu, memory, gpu, disk, network, processes
    var id: String { rawValue }
}

private final class TerminalScreen {
    private var lines: [[Character]] = [[]]
    private var row = 0
    private var column = 0
    private var savedRow = 0
    private var savedColumn = 0
    private var escapeCarry = ""
    private var eraseToEndPending = false

    var text: String {
        lines.map { line in
            var visible = line
            while visible.last == " " { visible.removeLast() }
            return String(visible)
        }.joined(separator: "\n")
    }

    func clear() {
        lines = [[]]
        row = 0
        column = 0
        savedRow = 0
        savedColumn = 0
        escapeCarry = ""
        eraseToEndPending = false
    }

    func feed(_ input: String) {
        let scalars = Array((escapeCarry + input).unicodeScalars)
        escapeCarry = ""
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar.value {
            case 27:
                guard index + 1 < scalars.count else {
                    escapeCarry = String(scalar)
                    trimHistory()
                    return
                }
                let next = scalars[index + 1]
                if next.value == 91 { // CSI: ESC [ ... final-byte
                    var end = index + 2
                    while end < scalars.count && !(64...126).contains(scalars[end].value) { end += 1 }
                    guard end < scalars.count else {
                        escapeCarry = scalars[index...].map { String($0) }.joined()
                        trimHistory()
                        return
                    }
                    let parameters = scalars[(index + 2)..<end].map { String($0) }.joined()
                    handleCSI(parameters: parameters, final: scalars[end])
                    index = end + 1
                } else if next.value == 93 { // OSC: ESC ] ... BEL or ESC \
                    var end = index + 2
                    var terminatorLength = 0
                    while end < scalars.count {
                        if scalars[end].value == 7 {
                            terminatorLength = 1
                            break
                        }
                        if scalars[end].value == 27,
                           end + 1 < scalars.count,
                           scalars[end + 1].value == 92 {
                            terminatorLength = 2
                            break
                        }
                        end += 1
                    }
                    guard terminatorLength > 0 else {
                        escapeCarry = scalars[index...].map { String($0) }.joined()
                        trimHistory()
                        return
                    }
                    index = end + terminatorLength
                } else {
                    if next.value == 55 {
                        savedRow = row
                        savedColumn = column
                    } else if next.value == 56 {
                        row = savedRow
                        column = savedColumn
                        ensureCursor()
                    }
                    index += 2
                }
            case 13: // Carriage return
                eraseToEndPending = false
                column = 0
                index += 1
            case 10: // Line feed
                eraseToEndPending = false
                row += 1
                column = 0
                ensureCursor()
                index += 1
            case 8: // Backspace
                eraseToEndPending = false
                column = max(0, column - 1)
                index += 1
            case 9: // Tab
                eraseToEndPending = false
                let destination = ((column / 8) + 1) * 8
                ensureLineWidth(destination)
                column = destination
                index += 1
            case 0...31, 127:
                index += 1
            default:
                eraseToEndPending = false
                put(Character(String(scalar)))
                index += 1
            }
        }
        trimHistory()
    }

    private func handleCSI(parameters: String, final: Unicode.Scalar) {
        let cleaned = parameters.trimmingCharacters(in: CharacterSet(charactersIn: "?<=>"))
        let values = cleaned.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        func value(_ position: Int, default fallback: Int = 1) -> Int {
            guard position < values.count, values[position] != 0 else { return fallback }
            return values[position]
        }

        switch final.value {
        case 65: row = max(0, row - value(0))                         // A: cursor up
        case 66: row += value(0); ensureCursor()                      // B: cursor down
        case 67: column = min(10_000, column + value(0))              // C: cursor forward
        case 68: column = max(0, column - value(0))                   // D: cursor back
        case 69: row += value(0); column = 0; ensureCursor()          // E: next line
        case 70: row = max(0, row - value(0)); column = 0             // F: previous line
        case 71: column = min(10_000, max(0, value(0) - 1))           // G: absolute column
        case 72, 102:                                                  // H/f: cursor position
            let targetRow = max(0, value(0) - 1)
            let targetColumn = min(10_000, max(0, value(1) - 1))
            if eraseToEndPending && targetRow == 0 && targetColumn == 0 { clear() }
            row = targetRow
            column = targetColumn
            ensureCursor()
        case 74:
            let mode = values.first ?? 0
            eraseDisplay(mode)                                        // J: erase display
            eraseToEndPending = mode == 0
        case 75: eraseLine(values.first ?? 0)                         // K: erase line
        case 80: deleteCharacters(value(0))                           // P: delete characters
        case 88: eraseCharacters(value(0))                            // X: erase characters
        case 115: savedRow = row; savedColumn = column                // s: save cursor
        case 117: row = savedRow; column = savedColumn; ensureCursor() // u: restore cursor
        default: break // Styling and terminal modes do not alter the text buffer.
        }
    }

    private func put(_ character: Character) {
        ensureCursor()
        ensureLineWidth(column)
        if column < lines[row].count {
            lines[row][column] = character
        } else {
            lines[row].append(character)
        }
        column += 1
    }

    private func ensureCursor() {
        row = min(row, 10_000)
        while lines.count <= row { lines.append([]) }
    }

    private func ensureLineWidth(_ width: Int) {
        ensureCursor()
        let space: Character = " "
        while lines[row].count < width { lines[row].append(space) }
    }

    private func eraseLine(_ mode: Int) {
        ensureCursor()
        let space: Character = " "
        switch mode {
        case 1:
            ensureLineWidth(column + 1)
            for index in 0...column { lines[row][index] = space }
        case 2:
            lines[row] = []
        default:
            if column < lines[row].count { lines[row].removeSubrange(column...) }
        }
    }

    private func eraseDisplay(_ mode: Int) {
        ensureCursor()
        if mode == 2 || mode == 3 {
            clear()
        } else if mode == 0 {
            eraseLine(0)
            if row + 1 < lines.count { lines.removeSubrange((row + 1)...) }
        }
    }

    private func deleteCharacters(_ count: Int) {
        ensureCursor()
        guard column < lines[row].count else { return }
        let end = min(lines[row].count, column + count)
        lines[row].removeSubrange(column..<end)
    }

    private func eraseCharacters(_ count: Int) {
        ensureLineWidth(column + count)
        let space: Character = " "
        for index in column..<(column + count) { lines[row][index] = space }
    }

    private func trimHistory() {
        guard lines.count > 6_000 else { return }
        lines.removeFirst(2_000)
        row = max(0, row - 2_000)
        savedRow = max(0, savedRow - 2_000)
    }
}

@main
struct RedTraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("RedTrace", id: "main") {
            RedTraceView(mode: .watcher, isDedicated: false)
                .frame(minWidth: 420, minHeight: 220)
        }
        .windowStyle(.hiddenTitleBar)

        WindowGroup("RedTrace Watcher", id: "watcher") {
            RedTraceView(mode: .watcher, isDedicated: true)
                .frame(minWidth: 420, minHeight: 220)
        }
        .windowStyle(.hiddenTitleBar)

        WindowGroup("RedTrace Runner", id: "runner") {
            RedTraceView(mode: .runner, isDedicated: true)
                .frame(minWidth: 420, minHeight: 220)
        }
        .windowStyle(.hiddenTitleBar)

        WindowGroup("RedTrace ChatGPT", id: "codex") {
            RedTraceView(mode: .codex, isDedicated: true)
                .frame(minWidth: 420, minHeight: 220)
        }
        .windowStyle(.hiddenTitleBar)

        WindowGroup("RedTrace System Monitor", id: "btop") {
            RedTraceView(mode: .btop, isDedicated: true)
                .frame(minWidth: 520, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("RedTrace", systemImage: "waveform.path.ecg") {
            RedTraceView(mode: .watcher, isDedicated: false)
                .frame(width: 720, height: 430)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        configureAllWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.configureAllWindows() }
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow { configure(window) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureAllWindows() {
        NSApp.windows.forEach(configure)
    }

    private func configure(_ window: NSWindow) {
        guard window.title.hasPrefix("RedTrace") else { return }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
    }
}

final class LogTailer: ObservableObject {
    struct Source: Identifiable, Hashable {
        let id: String
        let label: String
    }

    @Published var text = "Waiting for terminal output…\n"
    @Published var isPaused = false
    @Published var sources = [Source(id: logURL.path, label: "All terminals")]
    @Published var selectedSource = logURL.path {
        didSet {
            guard selectedSource != oldValue else { return }
            resetForSelectedSource()
        }
    }

    private var timer: Timer?
    private var offset: UInt64 = 0
    private let screen = TerminalScreen()
    private let trimAtCharacters = 400_000
    private let retainedCharacters = 250_000
    private var sourceRefreshCounter = 0

    private var selectedURL: URL { URL(fileURLWithPath: selectedSource) }

    init(startImmediately: Bool = true) {
        if startImmediately { activate() }
    }

    func activate() {
        guard timer == nil else { return }
        ensureLogExists()
        loadRecentContent()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.002
    }

    deinit { timer?.invalidate() }

    func clear() {
        try? Data().write(to: selectedURL, options: .atomic)
        offset = 0
        screen.clear()
        text = ""
    }

    private func tick() {
        sourceRefreshCounter += 1
        if sourceRefreshCounter >= 60 {
            sourceRefreshCounter = 0
            refreshSources()
        }
        readNewContent()
    }

    private func refreshSources() {
        let sessions = logURL.deletingLastPathComponent().appendingPathComponent("sessions")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let logs = urls.filter { $0.pathExtension == "log" && sessionIsActive($0) }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        let discovered = [Source(id: logURL.path, label: "All terminals")] + logs.prefix(24).map {
            let base = $0.deletingPathExtension().lastPathComponent
            return Source(id: $0.path, label: base.replacingOccurrences(of: "_", with: " "))
        }
        if discovered != sources { sources = discovered }
        if !discovered.contains(where: { $0.id == selectedSource }) {
            selectedSource = logURL.path
        }
    }

    private func sessionIsActive(_ log: URL) -> Bool {
        let marker = log.deletingPathExtension().appendingPathExtension("active")
        let markerPID = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filenameParts = log.deletingPathExtension().lastPathComponent.split(separator: "_")
        let filenamePID = filenameParts.count >= 2 ? String(filenameParts[filenameParts.count - 2]) : nil
        guard let rawPID = markerPID ?? filenamePID,
              let pid = Int32(rawPID),
              pid > 1 else {
            removeStaleSession(log: log, marker: marker)
            return false
        }

        if Darwin.kill(pid, 0) == 0 || errno == EPERM { return true }
        removeStaleSession(log: log, marker: marker)
        return false
    }

    private func removeStaleSession(log: URL, marker: URL) {
        try? FileManager.default.removeItem(at: log)
        try? FileManager.default.removeItem(at: marker)
    }

    private func resetForSelectedSource() {
        offset = 0
        screen.clear()
        text = "Waiting for terminal output…\n"
        ensureLogExists()
        loadRecentContent()
    }

    private func ensureLogExists() {
        let folder = selectedURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: selectedURL.path) {
            FileManager.default.createFile(atPath: selectedURL.path, contents: nil)
        }
        refreshSources()
    }

    private func loadRecentContent() {
        guard let handle = try? FileHandle(forReadingFrom: selectedURL) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 200_000 ? size - 200_000 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = size
        screen.feed(String(decoding: data, as: UTF8.self))
        let loaded = screen.text
        if !loaded.isEmpty { text = loaded }
    }

    private func readNewContent() {
        guard !isPaused,
              let attributes = try? FileManager.default.attributesOfItem(atPath: selectedURL.path),
              let number = attributes[.size] as? NSNumber else { return }

        let size = number.uint64Value
        if size < offset { offset = 0 }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: selectedURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)

        screen.feed(String(decoding: data, as: UTF8.self))
        text = screen.text
        if text.count > trimAtCharacters {
            text = String(text.suffix(retainedCharacters))
        }
    }
}

final class CommandSession: ObservableObject {
    @Published var input = ""
    @Published var isActive = false
    @Published var output = "Runner ready. Click the terminal or type a quick command below.\n"
    let terminal = TerminalModel()
    private let pty = PTYSession()
    private var history: [String] = []
    private var historyIndex: Int?
    private var renderTimer: Timer?
    private var pendingOutput = ""
    private let trimAtCharacters = 400_000
    private let retainedCharacters = 250_000

    init(startImmediately: Bool = true) {
        if startImmediately { activate() }
    }
    deinit {
        renderTimer?.invalidate()
        stop()
    }

    func activate() {
        if renderTimer == nil {
            renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.flushPendingOutput()
            }
            renderTimer?.tolerance = 0.002
        }
        if !isActive { start() }
    }

    func runInput() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        history.removeAll { $0 == command }
        history.append(command)
        historyIndex = nil
        input = ""

        send(Data((command + "\n").utf8))
    }

    func previousCommand() {
        guard !history.isEmpty else { return }
        let next = max(0, (historyIndex ?? history.count) - 1)
        historyIndex = next
        input = history[next]
    }

    func nextCommand() {
        guard let index = historyIndex else { return }
        let next = index + 1
        if next >= history.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = next
            input = history[next]
        }
    }

    func restart() {
        stop()
        appendOutput("\n— RedTrace shell restarted —\n")
        start()
    }

    func clearOutput() {
        pendingOutput = ""
        terminal.clear()
        output = ""
    }

    private func start() {
        do {
            pty.onData = { [weak self] data in self?.appendOutput(data) }
            pty.onExit = { [weak self] in self?.isActive = false }
            terminal.onResponse = { [weak self] data in self?.send(data) }
            try pty.start(columns: 100, rows: 30)
            isActive = true
        } catch {
            appendOutput("\nRedTrace could not start zsh: \(error.localizedDescription)\n")
        }
    }

    private func stop() {
        pty.stop()
        isActive = false
    }

    private func appendOutput(_ string: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingOutput.append(string)
        }
    }

    private func flushPendingOutput() {
        guard !pendingOutput.isEmpty else { return }
        terminal.feed(Data(pendingOutput.utf8))
        pendingOutput = ""
        output = terminal.lines().map { String($0.map(\.character)) }.joined(separator: "\n")
        if output.count > trimAtCharacters {
            output = String(output.suffix(retainedCharacters))
        }
    }

    private func appendOutput(_ data: Data) {
        DispatchQueue.main.async { [weak self] in self?.pendingOutput += String(decoding: data, as: UTF8.self) }
    }
    func send(_ data: Data) { pty.write(data) }
    func resize(columns: Int, rows: Int) { terminal.resize(columns: columns, rows: rows); pty.resize(columns: columns, rows: rows) }
}

final class CodexEventTailer: ObservableObject {
    @Published var text = "Waiting for Codex command events…\n"

    private let eventURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".redtrace/codex-events.jsonl")
    private var timer: Timer?
    private var offset: UInt64 = 0
    private var partialLine = ""
    private let trimAtCharacters = 400_000
    private let retainedCharacters = 250_000

    init(startImmediately: Bool = true) {
        if startImmediately { activate() }
    }

    deinit { timer?.invalidate() }

    func activate() {
        guard timer == nil else { return }
        ensureFile()
        loadRecentEvents()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.readNewEvents()
        }
        timer?.tolerance = 0.008
    }

    func clear() {
        try? Data().write(to: eventURL, options: .atomic)
        offset = 0
        partialLine = ""
        text = ""
    }

    private func ensureFile() {
        let folder = eventURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventURL.path) {
            FileManager.default.createFile(atPath: eventURL.path, contents: nil)
        }
    }

    private func loadRecentEvents() {
        guard let handle = try? FileHandle(forReadingFrom: eventURL) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 200_000 ? size - 200_000 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        offset = size
        var raw = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = raw.firstIndex(of: "\n") {
            raw = String(raw[raw.index(after: newline)...])
        }
        let rendered = consume(raw)
        if !rendered.isEmpty { text = rendered }
    }

    private func readNewEvents() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: eventURL.path),
              let number = attributes[.size] as? NSNumber else { return }
        let size = number.uint64Value
        if size < offset { offset = 0 }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: eventURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        text += consume(String(decoding: data, as: UTF8.self))
        if text.count > trimAtCharacters { text = String(text.suffix(retainedCharacters)) }
    }

    private func consume(_ raw: String) -> String {
        let combined = partialLine + raw
        let pieces = combined.split(separator: "\n", omittingEmptySubsequences: false)
        guard combined.hasSuffix("\n") else {
            partialLine = pieces.last.map(String.init) ?? combined
            return renderLines(pieces.dropLast().joined(separator: "\n"))
        }
        partialLine = ""
        return renderLines(combined)
    }

    private func renderLines(_ raw: String) -> String {
        raw.split(separator: "\n").compactMap { line -> String? in
            guard let data = String(line).data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data),
                  let object = value as? [String: Any] else { return nil }
            let origin = String(describing: object["origin"] ?? "local").uppercased()
            let phase = String(describing: object["phase"] ?? "")
            let cwd = String(describing: object["cwd"] ?? "")
            if phase == "start" {
                let command = String(describing: object["command"] ?? "")
                return "\n[\(origin)] \(cwd)\n❯ \(command)\n"
            }
            let output = String(describing: object["output"] ?? "")
            let body = output.isEmpty ? "" : output + (output.hasSuffix("\n") ? "" : "\n")
            return body + "[\(origin)] ✓ finished\n"
        }.joined()
    }
}

final class SystemMonitor: ObservableObject {
    @Published var cpu = "CPU —"
    @Published var gpu = "GPU —"
    @Published var ram = "RAM —"

    private var timer: Timer?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var gpuSampleCounter = 0

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer?.tolerance = 0.1
    }

    deinit { timer?.invalidate() }

    private func sample() {
        sampleCPU()
        sampleMemory()
        gpuSampleCounter += 1
        if gpuSampleCounter == 1 || gpuSampleCounter % 2 == 0 { sampleGPU() }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let current = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        if let previous = previousCPUTicks {
            let user = current.user - previous.user
            let system = current.system - previous.system
            let idle = current.idle - previous.idle
            let nice = current.nice - previous.nice
            let total = user + system + idle + nice
            if total > 0 {
                cpu = "CPU \(Int(round(Double(total - idle) * 100 / Double(total))))%"
            }
        }
        previousCPUTicks = current
    }

    private func sampleMemory() {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return }
        let percentage = min(100, Int(round(Double(usedPages * pageSize) * 100 / Double(totalBytes))))
        ram = "RAM \(percentage)%"
    }

    private func sampleGPU() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process()
            let output = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            task.arguments = ["-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"]
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                let patterns = [
                    #"Device Utilization %"\s*=\s*([0-9]+)"#,
                    #"GPU Activity\(%\)"\s*=\s*([0-9]+)"#
                ]
                var value: String?
                for pattern in patterns {
                    if let match = text.range(of: pattern, options: .regularExpression) {
                        let matched = String(text[match])
                        value = matched.split(whereSeparator: { !$0.isNumber }).last.map { String($0) }
                        if value != nil { break }
                    }
                }
                DispatchQueue.main.async { self?.gpu = value.map { "GPU \($0)%" } ?? "GPU —" }
            } catch {
                DispatchQueue.main.async { self?.gpu = "GPU —" }
            }
        }
    }
}

struct ProcessSample: Identifiable {
    let pid: Int
    let cpu: Double
    let memory: Double
    let command: String
    var id: Int { pid }
}

final class BtopMonitor: ObservableObject {
    @Published var cpu = 0.0
    @Published var memory = 0.0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var memoryHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var diskUsage = "—"
    @Published var networkDown = "—"
    @Published var networkUp = "—"
    @Published var totalProcesses = 0
    @Published var processes: [ProcessSample] = []

    private var timer: Timer?
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, time: Date)?
    private var samplingDetails = false

    init(startImmediately: Bool = true) {
        if startImmediately { activate() }
    }

    deinit { timer?.invalidate() }

    func activate() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer?.tolerance = 0.08
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDetails()
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let current = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        if let previous = previousCPUTicks {
            let busy = (current.user - previous.user) + (current.system - previous.system) + (current.nice - previous.nice)
            let idle = current.idle - previous.idle
            let total = busy + idle
            if total > 0 {
                cpu = min(100, Double(busy) * 100 / Double(total))
                append(cpu, to: &cpuHistory)
            }
        }
        previousCPUTicks = current
    }

    private func sampleMemory() {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let used = pages * UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return }
        memory = min(100, Double(used) * 100 / Double(total))
        append(memory, to: &memoryHistory)
    }

    private func sampleDetails() {
        guard !samplingDetails else { return }
        samplingDetails = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ps = Self.run("/bin/ps", ["-Ao", "pid=,pcpu=,pmem=,comm=", "-r"])
            let df = Self.run("/bin/df", ["-k", "/"])
            let netstat = Self.run("/usr/sbin/netstat", ["-ibn"])
            let allProcesses = Self.parseProcesses(ps)
            let processRows = Array(allProcesses.prefix(14))
            let disk = Self.parseDiskUsage(df)
            let totals = Self.parseNetworkTotals(netstat)
            DispatchQueue.main.async {
                guard let self else { return }
                self.processes = processRows
                self.totalProcesses = allProcesses.count
                self.diskUsage = disk
                self.updateNetwork(totals)
                self.samplingDetails = false
            }
        }
    }

    private func updateNetwork(_ totals: (received: UInt64, sent: UInt64)?) {
        guard let totals else {
            networkDown = "—"
            networkUp = "—"
            return
        }
        let now = Date()
        if let previous = previousNetwork {
            let seconds = max(0.1, now.timeIntervalSince(previous.time))
            let received = totals.received >= previous.received ? totals.received - previous.received : 0
            let sent = totals.sent >= previous.sent ? totals.sent - previous.sent : 0
            networkDown = Self.rate(Double(received) / seconds)
            networkUp = Self.rate(Double(sent) / seconds)
        }
        previousNetwork = (totals.received, totals.sent, now)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func parseProcesses(_ text: String) -> [ProcessSample] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard fields.count == 4,
                  let pid = Int(fields[0]),
                  let cpu = Double(fields[1]),
                  let memory = Double(fields[2]) else { return nil }
            return ProcessSample(pid: pid, cpu: cpu, memory: memory, command: String(fields[3]))
        }
    }

    private static func parseDiskUsage(_ text: String) -> String {
        guard let line = text.split(separator: "\n").last else { return "—" }
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        return fields.count > 4 ? String(fields[4]) : "—"
    }

    private static func parseNetworkTotals(_ text: String) -> (received: UInt64, sent: UInt64)? {
        let lines = text.split(separator: "\n")
        guard let headerIndex = lines.firstIndex(where: { $0.contains("Ibytes") && $0.contains("Obytes") }) else { return nil }
        let header = lines[headerIndex].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let inputIndex = header.firstIndex(of: "Ibytes"),
              let outputIndex = header.firstIndex(of: "Obytes") else { return nil }
        var interfaces: [String: (UInt64, UInt64)] = [:]
        for line in lines.dropFirst(headerIndex + 1) {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count > max(inputIndex, outputIndex) else { continue }
            let name = String(fields[0])
            guard name != "lo0",
                  let received = UInt64(fields[inputIndex]),
                  let sent = UInt64(fields[outputIndex]) else { continue }
            let old = interfaces[name] ?? (0, 0)
            interfaces[name] = (max(old.0, received), max(old.1, sent))
        }
        guard !interfaces.isEmpty else { return nil }
        return interfaces.values.reduce((UInt64(0), UInt64(0))) { ($0.0 + $1.0, $0.1 + $1.1) }
    }

    private static func rate(_ bytes: Double) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB/s", bytes / 1_048_576) }
        if bytes >= 1_024 { return String(format: "%.0f KB/s", bytes / 1_024) }
        return String(format: "%.0f B/s", bytes)
    }
}

struct RedTraceView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var tailer: LogTailer
    @StateObject private var commandSession: CommandSession
    @StateObject private var activityStore: ActivityStore
    private let opencodeBackend: ExternalMCPComputerBackend
    private let openComputerBackend: OpenComputerUseBackend
    @AppStorage("computerBackendChoice") private var computerBackendChoice = "opencode"
    @StateObject private var btopMonitor: BtopMonitor
    @StateObject private var systemMonitor = SystemMonitor()
    @AppStorage("windowOpacity") private var opacity = 0.85
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("fontName") private var fontName = "System Mono"
    @AppStorage("fontSize") private var fontSize = 12.0
    @AppStorage("textColorHex") private var textColorHex = "#FF4D5A"
    @AppStorage("backgroundColorHex") private var backgroundColorHex = "#000000"
    @AppStorage("themeDefaultsVersion") private var themeDefaultsVersion = 0
    @AppStorage("btopColumnCount") private var btopColumnCount = 0
    @AppStorage("mainLayoutMode") private var mainLayoutMode = "tabs"
    @AppStorage("dashboardColumnCount") private var dashboardColumnCount = 0
    @AppStorage("dashboardAutoFit") private var dashboardAutoFit = true
    @State private var showControls = true
    @State private var showAppearance = false
    @State private var showBtopLayout = false
    @State private var showDashboardLayout = false
    @State private var selectedMode: WindowMode
    @State private var isPinned = true
    @State private var btopTileOrder = MonitorTile.allCases
    @State private var btopTileHeights = Dictionary(
        uniqueKeysWithValues: MonitorTile.allCases.map { ($0, CGFloat(92)) }
    )
    @State private var draggedBtopTile: MonitorTile?
    @State private var dashboardPaneOrder = WindowMode.allCases
    @State private var visibleDashboardPanes = Set(WindowMode.allCases)
    @State private var dashboardPaneHeights = Dictionary(
        uniqueKeysWithValues: WindowMode.allCases.map { ($0, CGFloat(260)) }
    )
    @State private var draggedDashboardPane: WindowMode?
    private let isDedicated: Bool

    private let availableFonts = ["System Mono", "Menlo", "Monaco", "Courier New"]
    private let redAccent = Color(hex: "#FF3B4D")

    init(mode: WindowMode, isDedicated: Bool) {
        self.isDedicated = isDedicated
        _tailer = StateObject(wrappedValue: LogTailer(startImmediately: mode == .watcher))
        _commandSession = StateObject(wrappedValue: CommandSession(startImmediately: mode == .runner))
        let activityStore = ActivityStore()
        _activityStore = StateObject(wrappedValue: activityStore)
        opencodeBackend = ExternalMCPComputerBackend(activityStore: activityStore)
        openComputerBackend = OpenComputerUseBackend(activityStore: activityStore)
        _btopMonitor = StateObject(wrappedValue: BtopMonitor(startImmediately: mode == .btop))
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color(hex: backgroundColorHex).opacity(0.62)

            VStack(spacing: 0) {
                if showControls { toolbar }
                Divider().opacity(showControls ? 0.45 : 0)
                if usesCardLayout {
                    dashboardView
                } else if selectedMode == .btop {
                    btopView
                } else {
                    logView
                }
            }
        }
        .opacity(opacity)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(redAccent.opacity(0.28)))
        .overlay(alignment: .topTrailing) {
            if !showControls {
                Button { showControls = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .padding(9)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(redAccent.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(redAccent.opacity(0.9))
                .padding(16)
                .help("Show toolbar")
            }
        }
        .padding(8)
        .background(WindowLevelAccessor(isPinned: isPinned))
        .tint(redAccent)
        .onAppear {
            applyRedThemeDefaultsIfNeeded()
            if usesCardLayout { activateAllModes() }
            if computerBackendChoice != "off" { Task { try? await selectedComputerBackend.connect() } }
        }
        .onChange(of: mainLayoutMode) { newLayout in
            if newLayout == "cards" { activateAllModes() }
        }
        .onChange(of: selectedMode) { newMode in
            switch newMode {
            case .watcher: tailer.activate()
            case .runner: commandSession.activate()
            case .codex: if computerBackendChoice != "off" { Task { try? await selectedComputerBackend.connect() } }
            case .btop: btopMonitor.activate()
            case .chat: break
            }
        }
        .onChange(of: computerBackendChoice) { _ in
            opencodeBackend.stopControl()
            openComputerBackend.stopControl()
        }
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            if isDedicated {
                Label(dedicatedModeLabel, systemImage: dedicatedModeIcon)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(redAccent.opacity(0.95))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(redAccent.opacity(0.11), in: Capsule())
                    .overlay(Capsule().stroke(redAccent.opacity(0.2)))
                    .help("Dedicated \(dedicatedModeLabel) window")
            } else if !usesCardLayout {
                Picker("Mode", selection: $selectedMode) {
                    Text("WATCH").tag(WindowMode.watcher)
                    Text("RUN").tag(WindowMode.runner)
                    Text("CHATGPT").tag(WindowMode.codex)
                    Text("BTOP").tag(WindowMode.btop)
                    Text("CHAT").tag(WindowMode.chat)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 224, height: 22)
            } else {
                Menu {
                    ForEach(WindowMode.allCases) { mode in
                        Button {
                            toggleDashboardPane(mode)
                        } label: {
                            if visibleDashboardPanes.contains(mode) {
                                Label(dashboardTitle(for: mode), systemImage: "checkmark")
                            } else {
                                Text(dashboardTitle(for: mode))
                            }
                        }
                    }
                    Divider()
                    Button("Show All Cards") {
                        visibleDashboardPanes = Set(WindowMode.allCases)
                    }
                } label: {
                    Label("CARDS", systemImage: "rectangle.grid.2x2")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(redAccent.opacity(0.95))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(redAccent.opacity(0.11), in: Capsule())
                        .overlay(Capsule().stroke(redAccent.opacity(0.2)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(width: 24, height: 22, alignment: .center)
                .help("Choose which cards are visible")
            }
            if selectedMode == .watcher && !usesCardLayout {
                Menu {
                    ForEach(tailer.sources) { source in
                        Button {
                            tailer.selectedSource = source.id
                        } label: {
                            if source.id == tailer.selectedSource {
                                Label(source.label, systemImage: "checkmark")
                            } else {
                                Text(source.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Watching: \(selectedSourceLabel)")
            }
            WindowDragHandle()
                .frame(minWidth: 12, maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                .help("Drag the empty toolbar area to move window")
            HStack(spacing: 7) {
                Text(systemMonitor.cpu)
                Text(systemMonitor.gpu)
                Text(systemMonitor.ram)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
            Button { isPinned.toggle() } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin.slash")
            }
            .help(isPinned ? "Disable always on top" : "Keep window always on top")
            Menu {
                Button { openWindow(id: "watcher") } label: {
                    Label("New Watcher Window", systemImage: "eye")
                }
                Button { openWindow(id: "runner") } label: {
                    Label("New Runner Window", systemImage: "terminal")
                }
                Button { openWindow(id: "codex") } label: {
                    Label("New ChatGPT Window", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button { openWindow(id: "btop") } label: {
                    Label("New System Monitor", systemImage: "waveform.path.ecg")
                }
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Open a Watcher, Runner, ChatGPT, or System Monitor window")
            Button { showAppearance.toggle() } label: { Image(systemName: "paintpalette") }
                .help("Appearance")
                .popover(isPresented: $showAppearance, arrowEdge: .bottom) { appearancePanel }
            if !isDedicated {
                Button {
                    mainLayoutMode = usesCardLayout ? "tabs" : "cards"
                } label: {
                    Image(systemName: usesCardLayout ? "rectangle.split.1x2" : "rectangle.grid.2x2")
                }
                .help(usesCardLayout ? "Switch to tabs" : "Switch to cards")
            }
            if usesCardLayout {
                Button { showDashboardLayout.toggle() } label: { Image(systemName: "rectangle.3.group") }
                    .help("Card layout")
                    .popover(isPresented: $showDashboardLayout, arrowEdge: .bottom) { dashboardLayoutPanel }
            } else if selectedMode == .btop {
                Button { showBtopLayout.toggle() } label: { Image(systemName: "rectangle.3.group") }
                    .help("BTOP layout")
                    .popover(isPresented: $showBtopLayout, arrowEdge: .bottom) { btopLayoutPanel }
            }
            Button { wrapLines.toggle() } label: {
                Image(systemName: wrapLines ? "text.word.spacing" : "arrow.left.and.right.text.vertical")
            }.help("Toggle line wrapping")
            if !usesCardLayout && selectedMode == .watcher {
                Button { tailer.isPaused.toggle() } label: {
                    Image(systemName: tailer.isPaused ? "play.fill" : "pause.fill")
                }.help(tailer.isPaused ? "Resume" : "Pause")
                Button { tailer.clear() } label: { Image(systemName: "trash") }.help("Clear shared watcher log")
            } else if !usesCardLayout && selectedMode == .runner {
                Button { commandSession.clearOutput() } label: { Image(systemName: "trash") }.help("Clear runner output")
            } else if !usesCardLayout && selectedMode == .codex {
                Button { activityStore.clear() } label: { Image(systemName: "trash") }.help("Clear ChatGPT event log")
            }
            Button { showControls = false } label: { Image(systemName: "chevron.up") }.help("Hide controls")
        }
        .buttonStyle(.plain)
        .font(.system(size: 10))
        .foregroundStyle(redAccent.opacity(0.82))
        .padding(.horizontal, 9)
        .frame(height: 30)
    }

    private var usesCardLayout: Bool {
        !isDedicated && mainLayoutMode == "cards"
    }

    private var selectedComputerBackend: ComputerBackend {
        computerBackendChoice == "open" ? openComputerBackend : opencodeBackend
    }

    private func activateAllModes() {
        tailer.activate()
        commandSession.activate()
        btopMonitor.activate()
    }

    private var dedicatedModeLabel: String {
        switch selectedMode {
        case .watcher: return "WATCH"
        case .runner: return "RUN"
        case .codex: return "CHATGPT"
        case .btop: return "BTOP"
        case .chat: return "CHAT"
        }
    }

    private var dedicatedModeIcon: String {
        switch selectedMode {
        case .watcher: return "eye"
        case .runner: return "terminal"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .btop: return "waveform.path.ecg"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    private func applyRedThemeDefaultsIfNeeded() {
        guard themeDefaultsVersion < 1 else { return }
        opacity = 0.85
        textColorHex = "#FF4D5A"
        backgroundColorHex = "#000000"
        themeDefaultsVersion = 1
    }

    private var logView: some View {
        VStack(spacing: 0) {
            if selectedMode == .runner { InteractiveTerminalView(model: commandSession.terminal, send: commandSession.send) }
            else if selectedMode == .codex { ActivityView(store: activityStore, backend: selectedComputerBackend, backendChoice: $computerBackendChoice) }
            else { TerminalTextView(text: visibleText, fontName: fontName, fontSize: fontSize, textColor: NSColor(hex: textColorHex), wrapLines: wrapLines) }
            if selectedMode == .runner {
                Divider().opacity(0.45)
                commandBar
            }
        }
    }

    private var visibleText: String {
        switch selectedMode {
        case .watcher: return tailer.text
        case .runner: return commandSession.output
        case .codex: return ""
        case .btop: return ""
        case .chat: return ""
        }
    }

    private var selectedSourceLabel: String {
        tailer.sources.first(where: { $0.id == tailer.selectedSource })?.label ?? "All terminals"
    }

    private var dashboardView: some View {
        GeometryReader { geometry in
            let visiblePanes = dashboardPaneOrder.filter { visibleDashboardPanes.contains($0) }
            let columnCount = dashboardColumnCount == 0
                ? responsiveDashboardColumns(for: geometry.size.width)
                : max(1, min(4, dashboardColumnCount))
            let rowCount = max(1, Int(ceil(Double(visiblePanes.count) / Double(columnCount))))
            let availableHeight = geometry.size.height - 20 - CGFloat(max(0, rowCount - 1)) * 10
            let fittedHeight = max(180, floor(availableHeight / CGFloat(rowCount)))

            if visiblePanes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 24))
                    Text("No cards selected")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Click CARDS to choose what to show.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(redAccent.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 210), spacing: 10),
                            count: columnCount
                        ),
                        spacing: 10
                    ) {
                        ForEach(visiblePanes) { mode in
                            dashboardPane(mode, fittedHeight: dashboardAutoFit ? fittedHeight : nil)
                        }
                    }
                    .padding(10)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
    }

    private func toggleDashboardPane(_ mode: WindowMode) {
        if visibleDashboardPanes.contains(mode) {
            visibleDashboardPanes.remove(mode)
        } else {
            visibleDashboardPanes.insert(mode)
            switch mode {
            case .watcher: tailer.activate()
            case .runner: commandSession.activate()
            case .codex: break
            case .btop: btopMonitor.activate()
            case .chat: break
            }
        }
    }

    private func dashboardPane(_ mode: WindowMode, fittedHeight: CGFloat?) -> some View {
        ResizableDashboardPane(
            height: dashboardHeightBinding(for: mode, fittedHeight: fittedHeight),
            accent: dashboardAccent(for: mode)
        ) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: dashboardIcon(for: mode))
                    Text(dashboardTitle(for: mode))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))

                    if mode == .watcher {
                        Menu {
                            ForEach(tailer.sources) { source in
                                Button {
                                    tailer.selectedSource = source.id
                                } label: {
                                    if source.id == tailer.selectedSource {
                                        Label(source.label, systemImage: "checkmark")
                                    } else {
                                        Text(source.label)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Watching: \(selectedSourceLabel)")
                    }

                    if mode == .btop {
                        Button { showBtopLayout.toggle() } label: {
                            Image(systemName: "rectangle.3.group")
                        }
                        .buttonStyle(.plain)
                        .help("System monitor columns and layout")
                        .popover(isPresented: $showBtopLayout, arrowEdge: .bottom) {
                            btopLayoutPanel
                        }
                    }

                    Spacer()
                    Button { openWindow(id: mode.rawValue) } label: {
                        Image(systemName: "macwindow.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("Open dedicated \(dashboardTitle(for: mode)) window")

                    Image(systemName: "line.3.horizontal")
                        .padding(7)
                        .contentShape(Rectangle())
                        .onDrag {
                            draggedDashboardPane = mode
                            return NSItemProvider(object: mode.rawValue as NSString)
                        }
                        .help("Drag to move card")
                }
                .foregroundStyle(dashboardAccent(for: mode).opacity(0.88))
                .padding(.horizontal, 9)
                .frame(height: 30)

                Divider().opacity(0.32)
                dashboardPaneContent(mode)
            }
        }
        .onDrop(
            of: [UTType.text],
            delegate: DashboardPaneDropDelegate(
                destination: mode,
                panes: $dashboardPaneOrder,
                draggedPane: $draggedDashboardPane
            )
        )
    }

    @ViewBuilder
    private func dashboardPaneContent(_ mode: WindowMode) -> some View {
        switch mode {
        case .watcher:
            TerminalTextView(
                text: tailer.text,
                fontName: fontName,
                fontSize: fontSize,
                textColor: NSColor(hex: textColorHex),
                wrapLines: wrapLines
            )
        case .runner:
            VStack(spacing: 0) {
                InteractiveTerminalView(model: commandSession.terminal, send: commandSession.send)
                Divider().opacity(0.35)
                commandBar
            }
        case .codex: ActivityView(store: activityStore, backend: selectedComputerBackend, backendChoice: $computerBackendChoice)
        case .btop:
            btopView
        case .chat:
            CodexChatView(store: activityStore)
        }
    }

    private func dashboardTitle(for mode: WindowMode) -> String {
        switch mode {
        case .watcher: return "WATCH"
        case .runner: return "RUN"
        case .codex: return "CHATGPT"
        case .btop: return "BTOP"
        case .chat: return "CHAT"
        }
    }

    private func dashboardIcon(for mode: WindowMode) -> String {
        switch mode {
        case .watcher: return "eye"
        case .runner: return "terminal"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .btop: return "waveform.path.ecg"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }

    private func dashboardAccent(for mode: WindowMode) -> Color {
        switch mode {
        case .watcher: return .red
        case .runner: return .orange
        case .codex: return .pink
        case .btop: return .cyan
        case .chat: return .pink
        }
    }

    private func responsiveDashboardColumns(for width: CGFloat) -> Int {
        max(1, min(4, Int((width + 10) / 350)))
    }

    private func dashboardHeightBinding(for mode: WindowMode, fittedHeight: CGFloat?) -> Binding<CGFloat> {
        Binding(
            get: { fittedHeight ?? dashboardPaneHeights[mode] ?? 260 },
            set: {
                dashboardAutoFit = false
                dashboardPaneHeights[mode] = min(700, max(180, $0))
            }
        )
    }

    private var dashboardLayoutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Layout").font(.headline)
            Text("Drag each card’s header to rearrange it. Drag its lower-right corner to resize it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Fit cards to window", isOn: $dashboardAutoFit)

            Picker("Columns", selection: $dashboardColumnCount) {
                Text("AUTO").tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)

            Button("Reset card layout") {
                dashboardAutoFit = true
                dashboardColumnCount = 0
                dashboardPaneOrder = WindowMode.allCases
                dashboardPaneHeights = Dictionary(
                    uniqueKeysWithValues: WindowMode.allCases.map { ($0, CGFloat(260)) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var btopView: some View {
        GeometryReader { geometry in
            let columnCount = btopColumnCount == 0
                ? responsiveBtopColumns(for: geometry.size.width)
                : max(1, min(4, btopColumnCount))

            ScrollView {
                VStack(spacing: 10) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 105), spacing: 9),
                            count: columnCount
                        ),
                        spacing: 9
                    ) {
                        ForEach(btopTileOrder) { tile in
                            monitorTile(tile)
                        }
                    }

                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Text("PID").frame(width: 52, alignment: .trailing)
                            Text("CPU").frame(width: 52, alignment: .trailing)
                            Text("MEM").frame(width: 52, alignment: .trailing)
                            Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .frame(height: 27)

                        Divider().opacity(0.35)

                        ForEach(Array(btopMonitor.processes.enumerated()), id: \.element.id) { index, process in
                            HStack(spacing: 8) {
                                Text("\(process.pid)").frame(width: 52, alignment: .trailing)
                                Text(String(format: "%.1f%%", process.cpu)).frame(width: 52, alignment: .trailing)
                                Text(String(format: "%.1f%%", process.memory)).frame(width: 52, alignment: .trailing)
                                Text(process.command)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(index < 3 ? Color.red.opacity(0.95) : Color.white.opacity(0.78))
                            .padding(.horizontal, 10)
                            .frame(height: 23)
                            .background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                        }
                    }
                    .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))
                }
                .padding(10)
            }
        }
    }

    private func responsiveBtopColumns(for width: CGFloat) -> Int {
        max(1, min(4, Int((width + 9) / 220)))
    }

    private func monitorTile(_ tile: MonitorTile) -> some View {
        let title: String
        let value: String
        let history: [Double]
        let accent: Color

        switch tile {
        case .cpu:
            title = "CPU"
            value = String(format: "%.0f%%", btopMonitor.cpu)
            history = btopMonitor.cpuHistory
            accent = .red
        case .memory:
            title = "MEMORY"
            value = String(format: "%.0f%%", btopMonitor.memory)
            history = btopMonitor.memoryHistory
            accent = .orange
        case .gpu:
            title = "GPU"
            value = systemMonitor.gpu.replacingOccurrences(of: "GPU ", with: "")
            history = []
            accent = .purple
        case .disk:
            title = "DISK /"
            value = btopMonitor.diskUsage
            history = []
            accent = .pink
        case .network:
            title = "NETWORK"
            value = "↓ \(btopMonitor.networkDown)   ↑ \(btopMonitor.networkUp)"
            history = []
            accent = .cyan
        case .processes:
            title = "PROCESSES"
            value = "\(btopMonitor.totalProcesses)"
            history = []
            accent = .green
        }

        return ResizableMonitorCard(
            title: title,
            value: value,
            history: history,
            accent: accent,
            height: tileHeightBinding(for: tile)
        )
        .onDrag {
            draggedBtopTile = tile
            return NSItemProvider(object: tile.rawValue as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: MonitorTileDropDelegate(
                destination: tile,
                tiles: $btopTileOrder,
                draggedTile: $draggedBtopTile
            )
        )
    }

    private func tileHeightBinding(for tile: MonitorTile) -> Binding<CGFloat> {
        Binding(
            get: { btopTileHeights[tile] ?? 92 },
            set: { btopTileHeights[tile] = min(240, max(82, $0)) }
        )
    }

    private var btopLayoutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BTOP Layout").font(.headline)
            Text("Drag cards to rearrange them. Drag a card’s lower-right handle to change its height.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Columns", selection: $btopColumnCount) {
                Text("AUTO").tag(0)
                Text("1").tag(1)
                Text("2").tag(2)
                Text("3").tag(3)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)

            Button("Reset layout") {
                btopColumnCount = 0
                btopTileOrder = MonitorTile.allCases
                btopTileHeights = Dictionary(
                    uniqueKeysWithValues: MonitorTile.allCases.map { ($0, CGFloat(92)) }
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 290)
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Text("❯").foregroundStyle(Color(hex: textColorHex))
            TextField("Run a command…", text: $commandSession.input)
                .textFieldStyle(.plain)
                .font(.custom(fontName == "System Mono" ? "Menlo" : fontName, size: fontSize))
                .onSubmit { commandSession.runInput() }
            Menu {
                Menu("Navigation") {
                    commonCommand("Show current folder", command: "pwd")
                    commonCommand("List files", command: "ls -la")
                    commonCommand("Go up one folder", command: "cd ..")
                    commonCommand("Open folder in Finder", command: "open .")
                }
                Menu("Git") {
                    commonCommand("Status", command: "git status")
                    commonCommand("Recent commits", command: "git log --oneline -10")
                    commonCommand("Changed-file summary", command: "git diff --stat")
                    commonCommand("Current branch", command: "git branch --show-current")
                }
                Menu("System") {
                    commonCommand("Disk space", command: "df -h")
                    commonCommand("Largest folders", command: "du -sh * 2>/dev/null | sort -h")
                    commonCommand("Top CPU processes", command: "ps aux | sort -nrk 3 | head -15")
                    commonCommand("Network quality", command: "networkQuality")
                }
                Menu("Development") {
                    commonCommand("Swift version", command: "swift --version")
                    commonCommand("Xcode tools path", command: "xcode-select -p")
                    commonCommand("Python version", command: "python3 --version")
                    commonCommand("Node version", command: "node --version")
                }
                Divider()
                commonCommand("Clear terminal", command: "clear")
            } label: {
                Image(systemName: "command.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Common commands")
            Button { commandSession.previousCommand() } label: { Image(systemName: "chevron.up") }
                .help("Previous command")
            Button { commandSession.nextCommand() } label: { Image(systemName: "chevron.down") }
                .help("Next command")
            Button { commandSession.restart() } label: { Image(systemName: "stop.fill") }
                .help("Stop current command and restart shell")
            Button { commandSession.runInput() } label: { Image(systemName: "return") }
                .help("Run command")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.black.opacity(0.18))
    }

    private func commonCommand(_ title: String, command: String) -> some View {
        Button(title) { commandSession.input = command }
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance").font(.headline)

            Picker("Font", selection: $fontName) {
                ForEach(availableFonts, id: \.self) { Text($0).tag($0) }
            }

            HStack {
                Text("Font size")
                Slider(value: $fontSize, in: 9...24, step: 1)
                Text("\(Int(fontSize))").monospacedDigit().frame(width: 24)
            }

            HStack {
                Text("Window opacity")
                Slider(value: $opacity, in: 0.22...1.0)
                Text("\(Int(opacity * 100))%")
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }

            HStack {
                Text("Text color")
                Spacer()
                HexColorWell(hex: $textColorHex)
                    .frame(width: 44, height: 24)
            }

            HStack {
                Text("Background color")
                Spacer()
                HexColorWell(hex: $backgroundColorHex)
                    .frame(width: 44, height: 24)
            }

            Button("Reset appearance") {
                fontName = "System Mono"
                fontSize = 12
                opacity = 0.85
                textColorHex = "#FF4D5A"
                backgroundColorHex = "#000000"
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct ResizableDashboardPane<Content: View>: View {
    @Binding var height: CGFloat
    let accent: Color
    let content: Content
    @State private var resizeStartHeight: CGFloat?

    init(
        height: Binding<CGFloat>,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        _height = height
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.3)))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.78))
                    .padding(10)
                    .background(Color.black.opacity(0.25), in: Circle())
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { gesture in
                                if resizeStartHeight == nil { resizeStartHeight = height }
                                height = (resizeStartHeight ?? height) + gesture.translation.height
                            }
                            .onEnded { _ in resizeStartHeight = nil }
                    )
                    .help("Drag to resize card")
            }
            .frame(height: height)
    }
}

struct DashboardPaneDropDelegate: DropDelegate {
    let destination: WindowMode
    @Binding var panes: [WindowMode]
    @Binding var draggedPane: WindowMode?

    func dropEntered(info: DropInfo) {
        guard let draggedPane,
              draggedPane != destination,
              let sourceIndex = panes.firstIndex(of: draggedPane),
              let destinationIndex = panes.firstIndex(of: destination) else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            panes.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPane = nil
        return true
    }
}

struct MonitorCard: View {
    let title: String
    let value: String
    let history: [Double]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: value.count > 12 ? 12 : 19, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if !history.isEmpty {
                Sparkline(values: history, color: accent)
                    .frame(height: 24)
            } else {
                Capsule()
                    .fill(accent.opacity(0.22))
                    .overlay(alignment: .leading) { Capsule().fill(accent.opacity(0.7)).frame(width: 34) }
                    .frame(height: 3)
                    .padding(.vertical, 10.5)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.22)))
    }
}

struct ResizableMonitorCard: View {
    let title: String
    let value: String
    let history: [Double]
    let accent: Color
    @Binding var height: CGFloat
    @State private var resizeStartHeight: CGFloat?

    var body: some View {
        MonitorCard(title: title, value: value, history: history, accent: accent)
            .frame(height: height)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.55))
                    .padding(8)
                    .help("Drag card to move")
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.75))
                    .padding(9)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { gesture in
                                if resizeStartHeight == nil { resizeStartHeight = height }
                                height = (resizeStartHeight ?? height) + gesture.translation.height
                            }
                            .onEnded { _ in resizeStartHeight = nil }
                    )
                    .help("Drag to resize")
            }
    }
}

struct MonitorTileDropDelegate: DropDelegate {
    let destination: MonitorTile
    @Binding var tiles: [MonitorTile]
    @Binding var draggedTile: MonitorTile?

    func dropEntered(info: DropInfo) {
        guard let draggedTile,
              draggedTile != destination,
              let sourceIndex = tiles.firstIndex(of: draggedTile),
              let destinationIndex = tiles.firstIndex(of: destination) else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            tiles.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTile = nil
        return true
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let y = size.height * CGFloat(1 - min(100, max(0, value)) / 100)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1.5)
        }
        .background(
            LinearGradient(
                colors: [color.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

struct TerminalTextView: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: Double
    let textColor: NSColor
    let wrapLines: Bool

    final class Coordinator {
        var renderedText = ""
        var renderedFontName = ""
        var renderedFontSize = 0.0
        var renderedColor = NSColor.clear
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrapLines
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textColor = textColor
        textView.font = resolvedFont()
        configureWrapping(textView, in: scrollView)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let visibleBottom = scrollView.contentView.bounds.maxY
        let documentBottom = textView.bounds.maxY
        let shouldFollowOutput = coordinator.renderedText.isEmpty || visibleBottom >= documentBottom - 36
        let font = resolvedFont()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        if coordinator.renderedFontName != fontName ||
            coordinator.renderedFontSize != fontSize ||
            !coordinator.renderedColor.isEqual(textColor) {
            textView.font = font
            textView.textStorage?.addAttributes(attributes, range: NSRange(location: 0, length: textView.string.utf16.count))
            coordinator.renderedFontName = fontName
            coordinator.renderedFontSize = fontSize
            coordinator.renderedColor = textColor
        }

        if text.hasPrefix(coordinator.renderedText) {
            let newText = String(text.dropFirst(coordinator.renderedText.count))
            if !newText.isEmpty {
                textView.textStorage?.append(NSAttributedString(string: newText, attributes: attributes))
            }
        } else {
            let oldText = coordinator.renderedText as NSString
            let newText = text as NSString
            let prefix = oldText.commonPrefix(with: text, options: []) as NSString
            let prefixLength = prefix.length
            let oldSuffixRange = NSRange(location: prefixLength, length: oldText.length - prefixLength)
            let newSuffix = newText.substring(from: prefixLength)
            textView.textStorage?.replaceCharacters(
                in: oldSuffixRange,
                with: NSAttributedString(string: newSuffix, attributes: attributes)
            )
        }

        coordinator.renderedText = text
        scrollView.hasHorizontalScroller = !wrapLines
        configureWrapping(textView, in: scrollView)

        if shouldFollowOutput {
            DispatchQueue.main.async {
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                let bottom = max(0, textView.bounds.height - scrollView.contentSize.height)
                let horizontalPosition = wrapLines ? 0 : scrollView.contentView.bounds.origin.x
                scrollView.contentView.scroll(to: NSPoint(x: horizontalPosition, y: bottom))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    private func resolvedFont() -> NSFont {
        if fontName == "System Mono" {
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        return NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func configureWrapping(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        if wrapLines {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}

struct HexColorWell: NSViewRepresentable {
    @Binding var hex: String

    final class Coordinator: NSObject {
        var value: Binding<String>

        init(value: Binding<String>) {
            self.value = value
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            value.wrappedValue = sender.color.hexRGB
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $hex)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.color = NSColor(hex: hex)
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.value = $hex
        let updated = NSColor(hex: hex)
        if !well.color.isEqual(updated) { well.color = updated }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexRGB: String {
        guard let rgb = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}

struct WindowLevelAccessor: NSViewRepresentable {
    let isPinned: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = isPinned ? .floating : .normal
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
