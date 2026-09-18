import SwiftUI

final class CodexChatSession: ObservableObject {
    @Published var messages: [(id: UUID, text: String, isUser: Bool)] = []
    @Published var input = ""
    @Published var isRunning = false
    @Published var status = "Disconnected"
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var threadID: String?

    deinit { process?.terminate() }
    func newChat() { threadID = nil; messages.removeAll() }
    func stop() { send(method: "turn/interrupt", params: threadID.map { ["threadId": $0] } ?? [:]); isRunning = false }
    func sendCurrent() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        input = ""; messages.append((UUID(), text, true)); isRunning = true; status = "Connecting"
        ensureServer {
            if let threadID = self.threadID { self.startTurn(threadID, text: text) }
            else { self.send(method: "thread/start", params: [:]) { result in
                self.threadID = result["threadId"] as? String ?? (result["thread"] as? [String: Any])?["id"] as? String
                if let id = self.threadID { self.startTurn(id, text: text) } else { self.status = "Thread start failed"; self.isRunning = false }
            } }
        }
    }
    private func ensureServer(_ ready: @escaping () -> Void) {
        if process != nil { ready(); return }
        guard let codex = Self.findCodex() else { status = "Codex CLI not found"; isRunning = false; return }
        let process = Process(), input = Pipe(), output = Pipe(); process.executableURL = codex; process.arguments = ["app-server", "--listen", "stdio://"]; process.standardInput = input; process.standardOutput = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in self?.receive(handle.availableData) }; process.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.process = nil; self?.isRunning = false; self?.status = "Disconnected" } }
        do { try process.run() } catch { status = error.localizedDescription; return }; self.process = process; stdin = input.fileHandleForWriting
        send(method: "initialize", params: ["clientInfo": ["name": "RedTrace", "version": "1.0"]]) { _ in self.status = "Connected"; ready() }
    }
    private func startTurn(_ threadID: String, text: String) { send(method: "turn/start", params: ["threadId": threadID, "input": [["type": "text", "text": text]]]) }
    private func send(method: String, params: [String: Any], completion: (([String: Any]) -> Void)? = nil) { let id = nextID; nextID += 1; pending[id] = completion; guard let stdin, let data = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params]) else { return }; stdin.write(data); stdin.write(Data([10])) }
    private var pending: [Int: (([String: Any]) -> Void)?] = [:]
    private func receive(_ data: Data) { guard !data.isEmpty else { return }; buffer.append(data); while let newline = buffer.firstIndex(of: 10) { let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline); guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }; if let id = object["id"] as? Int, let completion = pending.removeValue(forKey: id) ?? nil { completion(object["result"] as? [String: Any] ?? [:]) }; guard let method = object["method"] as? String else { continue }; let params = object["params"] as? [String: Any] ?? [:]; if method.contains("delta") { let delta = params["delta"] as? String ?? params["text"] as? String ?? ""; if !delta.isEmpty { DispatchQueue.main.async { if let last = self.messages.last, !last.isUser { self.messages[self.messages.count - 1].text += delta } else { self.messages.append((UUID(), delta, false)) } } } }; if method.contains("completed") || method.contains("failed") { DispatchQueue.main.async { self.isRunning = false } } } }
    private static func findCodex() -> URL? { let fm = FileManager.default; let paths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex", fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path]; return paths.first { fm.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:)) }
}

struct CodexChatView: View {
    @StateObject private var session = CodexChatSession()
    @ObservedObject var store: ActivityStore
    @State private var followsLatest = true
    var body: some View {
        VStack(spacing: 6) {
            HStack { Text(session.status).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("New Chat") { session.newChat() }.buttonStyle(.borderless); Button("Stop") { session.stop() }.buttonStyle(.borderless).disabled(!session.isRunning) }
            ScrollViewReader { proxy in ScrollView { LazyVStack(alignment: .leading, spacing: 8) { ForEach(session.messages, id: \.id) { message in Text(message.text).padding(8).background(message.isUser ? Color.red.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading) }; if session.isRunning { HStack(spacing: 4) { Circle().frame(width: 5, height: 5); Circle().frame(width: 5, height: 5); Circle().frame(width: 5, height: 5) }.foregroundStyle(.red).opacity(0.8).padding(8).transition(.opacity).animation(.easeInOut(duration: 0.7).repeatForever(), value: session.isRunning) }; Color.clear.frame(height: 1).id("chat-end") }.padding(.horizontal, 10) }.onChange(of: session.messages.count) { _ in guard followsLatest else { return }; DispatchQueue.main.async { proxy.scrollTo("chat-end", anchor: .bottom) } }.overlay(alignment: .bottomTrailing) { if !followsLatest { Button("Jump to Latest") { followsLatest = true; proxy.scrollTo("chat-end", anchor: .bottom) }.buttonStyle(.borderedProminent).controlSize(.small).padding(8) } } }
            HStack { TextField("Message Codex…", text: $session.input, axis: .vertical).textFieldStyle(.roundedBorder); Button("Send") { session.sendCurrent() }.buttonStyle(.borderedProminent).disabled(session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            .padding(.horizontal, 10)
        }
    }
}
