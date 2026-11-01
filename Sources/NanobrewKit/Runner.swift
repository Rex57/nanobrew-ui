import Foundation

/// One nb run: started at an absolute path with an argv list (never a shell), in its own process group.
public final class NBProcess: @unchecked Sendable {
    public let pid: pid_t
    /// stdout and stderr lines, ANSI codes removed. The stream ends after the process exits.
    public let lines: AsyncStream<String>
    private let lock = NSLock()
    private var waitStatus: Int32 = 0
    private var cancelled = false

    public init(path: String, args: [String]) throws {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw POSIXError(.EMFILE) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Own process group, so Cancel reaches nb's children; no other fd leaks into the child.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attr, 0)

        let argv = ([path] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let err = posix_spawn(&pid, path, &actions, &attr, argv, environ)
        close(fds[1])
        guard err == 0 else {
            close(fds[0])
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .ENOENT)
        }
        self.pid = pid

        let (stream, continuation) = AsyncStream<String>.makeStream()
        lines = stream
        let readFD = fds[0]
        Thread.detachNewThread { [self] in
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(readFD, &buffer, buffer.count)
                if n <= 0 { break }
                pending.append(contentsOf: buffer[0..<n])
                while let newline = pending.firstIndex(of: 10) {
                    continuation.yield(Self.clean(pending[pending.startIndex..<newline]))
                    pending.removeSubrange(pending.startIndex...newline)
                }
            }
            if !pending.isEmpty { continuation.yield(Self.clean(pending)) }
            close(readFD)
            var status: Int32 = 0
            while waitpid(self.pid, &status, 0) == -1 && errno == EINTR {}
            lock.withLock { waitStatus = status }
            continuation.finish()
        }
    }

    /// Stops the whole process group.
    public func cancel() {
        lock.withLock { cancelled = true }
        // shortcut: SIGTERM only, no SIGKILL fallback; add one if nb ever ignores SIGTERM.
        kill(-pid, SIGTERM)
    }

    public var wasCancelled: Bool { lock.withLock { cancelled } }

    /// The exit code, or nil when a signal ended the process. Valid once `lines` has ended.
    public var exitCode: Int32? {
        let status = lock.withLock { waitStatus }
        return status & 0x7f == 0 ? (status >> 8) & 0xff : nil
    }

    static func clean(_ bytes: Data) -> String {
        stripANSI(String(decoding: bytes, as: UTF8.self)).replacingOccurrences(of: "\r", with: "")
    }
}

/// Removes ANSI escape sequences (CSI and OSC) from nb's output.
public func stripANSI(_ text: String) -> String {
    text.replacing(/\x1B\[[0-?]*[ -\/]*[@-~]|\x1B\][^\x07\x1B]*(\x07|\x1B\\)|\x1B[@-_]/, with: "")
}
