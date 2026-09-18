import SwiftUI

struct ActivityEvent: Identifiable { let id:String; let timestamp:Date; var phase:String; var origin:String; var tool:String; var command:String; var target:String; var output:String; var exitCode:String; var duration:TimeInterval?; var category:String; var raw:String }
final class ActivityStore: ObservableObject {
    @Published private(set) var events:[ActivityEvent]=[]; private let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".redtrace/codex-events.jsonl"); private var offset:UInt64=0; private var partial=""; private var starts:[String:ActivityEvent]=[:]; private var timer:Timer?
    init(){timer=Timer.scheduledTimer(withTimeInterval:1.0/12,repeats:true){[weak self]_ in self?.read()}}
    deinit{timer?.invalidate()}; func clear(){try? Data().write(to:url);events=[];offset=0;partial=""}
    private func read(){guard let attrs=try? FileManager.default.attributesOfItem(atPath:url.path),let size=(attrs[.size] as? NSNumber)?.uint64Value else{return};if size<offset{offset=0};guard size>offset,let h=try? FileHandle(forReadingFrom:url)else{return};defer{try?h.close()};try?h.seek(toOffset:offset);let d=(try?h.readToEnd()) ?? Data();offset += UInt64(d.count);let text=partial+String(decoding:d,as:UTF8.self);let parts=text.split(separator:"\n",omittingEmptySubsequences:false);partial=text.hasSuffix("\n") ? "" : String(parts.last ?? "");for line in (text.hasSuffix("\n") ? parts : parts.dropLast()){parse(String(line))}}
    private func parse(_ raw:String){guard let d=raw.data(using:.utf8),let o=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] else{return};let phase="\(o["phase"] ?? "finish")", tool="\(o["tool_name"] ?? "tool")", command="\(o["command"] ?? "")", input=o["tool_input"].map{"\($0)"} ?? "", target="\(o["target"] ?? o["path"] ?? o["file_path"] ?? o["query"] ?? "")", key="\(o["tool_use_id"] ?? o["session_id"] ?? UUID().uuidString)";let now=ISO8601DateFormatter().date(from:"\(o["timestamp"] ?? "")") ?? Date();var e=ActivityEvent(id:key,timestamp:now,phase:phase,origin:"\(o["origin"] ?? "local")",tool:tool,command:command,target:target,output:"\(o["output"] ?? "")",exitCode:"\(o["exit_code"] ?? "")",duration:nil,category:ActivityStore.category(tool,command),raw:raw+"\n"+input);if phase=="start" {starts[key]=e;return};if let start=starts.removeValue(forKey:key){e.duration=now.timeIntervalSince(start.timestamp);if e.command.isEmpty{e.command=start.command};if e.target.isEmpty{e.target=start.target}};events.append(e);if events.count>3000{events.removeFirst(events.count-3000)} }
    static func category(_ tool:String,_ command:String)->String{let x=(tool+" "+command).lowercased();if x.contains("git "){return "git"};if x.contains("build")||x.contains("xcodebuild"){return "build"};if x.contains("test")||x.contains("pytest"){return "test"};if x.contains("rg ")||x.contains("grep")||x.contains("search"){return "search"};if x.contains("read")||x.contains("get-content")||x.contains("cat "){return "read"};if x.contains("edit")||x.contains("write"){return "edit"};if x.contains("curl")||x.contains("wget"){return "network"};return command.isEmpty ? "tool" : "command"}
    func description(_ e:ActivityEvent)->String{if e.category=="search",!e.target.isEmpty{return "Searching \(e.target)"};if !e.target.isEmpty{return e.target};if !e.command.isEmpty{return e.command};return "\(e.tool) activity"}
    func recordComputerAction(_ action:ComputerAction,phase:String,result:[String:Any]?=nil){DispatchQueue.main.async{let now=Date();self.events.append(ActivityEvent(id:"computer-\(UUID().uuidString)",timestamp:now,phase:phase,origin:"computer",tool:action.tool,command:action.description,target:"",output:result.map{String(describing:$0)} ?? "",exitCode:"",duration:nil,category:"computer",raw:"computer \(phase): \(action.description)"));if self.events.count>3000{self.events.removeFirst(self.events.count-3000)}}}
    func recordBackendEvent(_ message:String){DispatchQueue.main.async{let now=Date();self.events.append(ActivityEvent(id:"backend-\(UUID().uuidString)",timestamp:now,phase:"finish",origin:"computer",tool:"computer_backend",command:message,target:"",output:"",exitCode:"",duration:nil,category:"computer",raw:message));if self.events.count>3000{self.events.removeFirst(self.events.count-3000)}}}
}
private struct ActivityBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ActivityView: View {
    @ObservedObject var store: ActivityStore
    let backend: ComputerBackend
    @Binding var backendChoice: String
    @AppStorage("chatGPTActivityMode") private var mode = "Normal"
    @State private var followsLatest = true
    @State private var programmaticScroll = false
    @State private var establishedBottom = false
    @State private var jumpRequest = 0
    @State private var showChat = false
    @State private var computerEnabled = false
    @State private var captureEnabled = false
    @State private var inputEnabled = false
    @State private var permissionStatus = ComputerPermissionStatus()

    private let latestID = "activity-latest"

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("Minimal").tag("Minimal")
                Text("Normal").tag("Normal")
                Text("Verbose").tag("Verbose")
            }
            .pickerStyle(.segmented)
            .padding(8)

            Picker("", selection: $showChat) { Text("Activity").tag(false); Text("Chat").tag(true) }
                .pickerStyle(.segmented)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            if showChat {
                CodexChatView(store: store)
            } else {
                computerControlPanel

                ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(store.events) { event in
                                eventView(event)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(latestID)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ActivityBottomOffsetKey.self,
                                        value: geometry.frame(in: .named("activity-scroll")).minY
                                    )
                                })
                        }
                        .padding(10)
                    }
                    .coordinateSpace(name: "activity-scroll")
                    .onPreferenceChange(ActivityBottomOffsetKey.self) { bottomOffset in
                        // The sentinel sits inside the scroll content. It is near the viewport's
                        // bottom only when the user has not scrolled away from recent activity.
                        guard !programmaticScroll else { return }
                        let nearBottom = bottomOffset <= viewport.size.height + 36
                        if nearBottom {
                            establishedBottom = true
                            followsLatest = true
                        } else if establishedBottom {
                            followsLatest = false
                        }
                    }
                    .onChange(of: store.events.count) { _ in
                        guard followsLatest || !establishedBottom else { return }
                        programmaticScroll = true
                        DispatchQueue.main.async {
                            proxy.scrollTo(latestID, anchor: .bottom)
                            DispatchQueue.main.async {
                                programmaticScroll = false
                                followsLatest = true
                            }
                        }
                    }
                    .onChange(of: jumpRequest) { _ in
                        followsLatest = true
                        establishedBottom = true
                        programmaticScroll = true
                        proxy.scrollTo(latestID, anchor: .bottom)
                        DispatchQueue.main.async { programmaticScroll = false }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !store.events.isEmpty {
                            Button(followsLatest ? "Following Latest" : "Jump to Latest") {
                                followsLatest = true
                                establishedBottom = true
                                programmaticScroll = true
                                DispatchQueue.main.async {
                                    proxy.scrollTo(latestID, anchor: .bottom)
                                    DispatchQueue.main.async {
                                        programmaticScroll = false
                                        followsLatest = true
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(12)
                        }
                    }
                    .onAppear {
                        programmaticScroll = true
                        DispatchQueue.main.async {
                            proxy.scrollTo(latestID, anchor: .bottom)
                            DispatchQueue.main.async {
                                programmaticScroll = false
                                followsLatest = true
                            }
                        }
                    }
                }
            }
            }
        }
    }

    private var computerControlPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Picker("Backend", selection: $backendChoice) { Text("opencode").tag("opencode"); Text("Open Computer Use").tag("open"); Text("Off").tag("off") }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                Toggle("Computer Control", isOn: Binding(get: { computerEnabled }, set: setComputerEnabled))
                    .toggleStyle(.switch)
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(backendChoice == "off")
                Spacer()
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                Button("Stop Control") { stopComputerControl() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(!computerEnabled)
            }
            if computerEnabled {
                HStack(spacing: 12) {
                    Toggle("Capture", isOn: $captureEnabled)
                        .disabled(!backend.capabilities.contains(.screenRead))
                    Toggle("Input Control", isOn: $inputEnabled)
                        .disabled(backend.capabilities.intersection([.pointerInput, .keyboardInput, .scrolling]).isEmpty)
                    Spacer()
                    Text("AX \(permissionStatus.accessibility ? "✓" : "–")  Screen \(permissionStatus.screenRecording ? "✓" : "–")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .font(.caption2)
            }
            HStack {
                Spacer()
                Button(followsLatest ? "Following Latest" : "Follow Latest") { jumpRequest += 1 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .background(Color.black.opacity(0.18))
        .task(id: computerEnabled) {
            while computerEnabled {
                if backend.status == .connected, let permissions = try? await backend.permissions() { permissionStatus = permissions }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onChange(of: backendChoice) { _ in stopComputerControl() }
    }

    private var statusLabel: String { switch backend.status { case .connected: return "Connected"; case .connecting: return "Connecting"; case .disconnected: return "Disconnected"; case .unavailable: return "Error" } }
    private var statusColor: Color { switch backend.status { case .connected: return .green; case .connecting: return .orange; case .disconnected: return .secondary; case .unavailable: return .red } }
    private func setComputerEnabled(_ enabled: Bool) { computerEnabled = enabled; if enabled { Task { do { try await backend.connect(); if let permissions = try? await backend.permissions() { permissionStatus = permissions }; store.recordBackendEvent("connected") } catch { store.recordBackendEvent("connection error") } } } else { stopComputerControl() } }
    private func stopComputerControl() { computerEnabled = false; captureEnabled = false; inputEnabled = false; backend.stopControl(); store.recordBackendEvent("control stopped") }

    @ViewBuilder
    private func eventView(_ event: ActivityEvent) -> some View {
        if mode == "Verbose" {
            Text("\(event.timestamp) \(event.phase.uppercased()) \(event.origin.uppercased())\nTOOL \(event.tool)\nCMD \(event.command)\nTARGET \(event.target)\n\(event.output)\n\(event.raw)")
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top) {
                Image(systemName: event.category == "edit" ? "pencil" : event.category == "build" ? "hammer" : "magnifyingglass")
                    .foregroundStyle(event.category == "edit" ? .pink : .orange)
                VStack(alignment: .leading) {
                    Text("\(event.category.uppercased())  \(store.description(event))")
                        .font(.system(size: 12, weight: .semibold))
                    if mode == "Normal" {
                        let metadata = event.origin.uppercased() + (event.duration.map { String(format: " · %.1fs", $0) } ?? "")
                        Text(event.command)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
