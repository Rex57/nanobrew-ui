import Foundation

/// One nb run: started at an absolute path with an argv list (never a shell), in its own process group.
public final class NBProcess: @unchecked Sendable {
    public let pid: pid_t
    /// stdout and stderr lines (only stdout with `separateStderr`), ANSI codes removed, one batch per read.
    /// The stream ends after the process exits.
    public let lines: AsyncStream<[String]>
    private let lock = NSLock()
    /// nil until waitpid reaped the process.
    private var waitStatus: Int32?
    private var cancelled = false
    /// True once Cancel had to send SIGKILL.
    var killed: Bool { lock.withLock { killedFlag } }
    private var killedFlag = false
    private var stderrData = Data()

    public init(path: String, args: [String], separateStderr: Bool = false) throws {
        var fds: [Int32] = [0, 0]
        var errFDs: [Int32] = [-1, -1]
        guard pipe(&fds) == 0, !separateStderr || pipe(&errFDs) == 0 else { throw POSIXError(.EMFILE) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, separateStderr ? errFDs[1] : fds[1], 2)
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
        if separateStderr { close(errFDs[1]) }
        guard err == 0 else {
            close(fds[0])
            if separateStderr { close(errFDs[0]) }
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .ENOENT)
        }
        self.pid = pid

        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        lines = stream
        let readFD = fds[0]
        let stderrDone = DispatchSemaphore(value: 0)
        if separateStderr {
            let errFD = errFDs[0]
            Thread.detachNewThread { [self] in
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    let n = read(errFD, &buffer, buffer.count)
                    if n <= 0 { break }
                    lock.withLock { stderrData.append(contentsOf: buffer[0..<n]) }
                }
                close(errFD)
                stderrDone.signal()
            }
        } else {
            stderrDone.signal()
        }
        Thread.detachNewThread { [self] in
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(readFD, &buffer, buffer.count)
                if n <= 0 { break }
                pending.append(contentsOf: buffer[0..<n])
                guard let last = pending.lastIndex(of: 10) else { continue }
                let complete = pending[pending.startIndex..<last]
                continuation.yield(complete.split(separator: 10, omittingEmptySubsequences: false).map(Self.clean))
                pending.removeSubrange(pending.startIndex...last)
            }
            if !pending.isEmpty { continuation.yield([Self.clean(pending)]) }
            close(readFD)
            stderrDone.wait()
            // Wait for the exit without reaping, then reap under the lock: Cancel's SIGKILL checks `waitStatus`
            // under the same lock, so it never reaches a pid that was reaped and maybe reused.
            var info = siginfo_t()
            while waitid(P_PID, id_t(self.pid), &info, WEXITED | WNOWAIT) == -1 && errno == EINTR {}
            lock.withLock {
                var status: Int32 = 0
                while waitpid(self.pid, &status, 0) == -1 && errno == EINTR {}
                waitStatus = status
            }
            continuation.finish()
        }
    }

    /// Stops the whole process group: SIGTERM now, SIGKILL when the process was not reaped `killAfter` later (D4).
    public func cancel(killAfter grace: Duration = .seconds(5)) {
        lock.withLock { cancelled = true }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(grace / .milliseconds(1)))) { [self] in
            lock.withLock {
                guard waitStatus == nil else { return }
                kill(-pid, SIGKILL)
                killedFlag = true
            }
        }
    }

    public var wasCancelled: Bool { lock.withLock { cancelled } }

    /// stderr lines with `separateStderr`, ANSI codes removed. Valid once `lines` has ended.
    public var stderrLines: [String] {
        let data = lock.withLock { stderrData }
        return data.isEmpty ? [] : data.split(separator: 10).map(Self.clean)
    }

    /// The exit code; nil while the process was not reaped (for example a read that was cancelled) or when a signal
    /// ended it.
    public var exitCode: Int32? {
        guard let status = lock.withLock({ waitStatus }) else { return nil }
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
