import Foundation
import Darwin

final class PTYSession {
    private(set) var masterFD: Int32 = -1
    private(set) var pid: pid_t = -1
    private var reader: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "redtrace.pty.write")
    var onData: ((Data) -> Void)?
    var onExit: (() -> Void)?

    func start(columns: Int, rows: Int) throws {
        stop()
        var size = winsize(ws_row: UInt16(max(1, rows)), ws_col: UInt16(max(2, columns)), ws_xpixel: 0, ws_ypixel: 0)
        var fd: Int32 = -1
        let child = forkpty(&fd, nil, nil, &size)
        if child < 0 { throw NSError(domain: "RedTrace.PTY", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
        if child == 0 {
            setenv("TERM", "xterm-256color", 1); setenv("REDTRACE_ATTACHED", "1", 1)
            let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/zsh"), strdup("-il"), nil]
            execve("/bin/zsh", argv, environ); _exit(127)
        }
        masterFD = fd; pid = child
        let flags = fcntl(fd, F_GETFL); _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { }
        reader = source; source.resume()
    }
    func write(_ data: Data) { guard masterFD >= 0 else { return }; let fd=masterFD; writeQueue.async { data.withUnsafeBytes { raw in var offset=0; while offset < raw.count { let result = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count-offset); if result > 0 {offset += result} else if errno == EINTR {continue} else {break} } } } }
    func resize(columns: Int, rows: Int) { guard masterFD >= 0 else {return}; var size=winsize(ws_row:UInt16(max(1,rows)),ws_col:UInt16(max(2,columns)),ws_xpixel:0,ws_ypixel:0); _ = ioctl(masterFD, TIOCSWINSZ, &size) }
    private func readAvailable() { guard masterFD >= 0 else{return}; var bytes=[UInt8](repeating:0,count:8192); while true { let count=Darwin.read(masterFD,&bytes,bytes.count); if count>0 {onData?(Data(bytes.prefix(Int(count))))} else if count==0 || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { let close = errno == EIO || count == 0; if close { DispatchQueue.main.async { [weak self] in self?.onExit?() } }; break } else {break} } }
    func stop() { reader?.cancel(); reader=nil; let fd=masterFD; masterFD = -1; if fd >= 0 { _=Darwin.close(fd) }; let child=pid; pid = -1; guard child > 0 else{return}; Darwin.kill(child,SIGHUP); DispatchQueue.global(qos:.utility).async { var status:Int32=0; var waited=0; while waitpid(child,&status,WNOHANG)==0 && waited < 20 { usleep(50_000); waited += 1 }; if waited >= 20 { Darwin.kill(child,SIGTERM); _=waitpid(child,&status,0) } } }
    deinit { stop() }
}
