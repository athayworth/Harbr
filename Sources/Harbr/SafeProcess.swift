//
//  SafeProcess.swift
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

import Foundation
import Darwin
import HarbrSafe
import os

/// Subprocess + port-check helpers that don't crash Harbr when something
/// fails — especially under memory pressure, where `Process.run()` / NSTask
/// can raise an Objective-C exception that bypasses Swift's `try` and
/// triggers `abort()`. All call sites in the app should go through here.
enum SafeProcess {
    private static let log = Logger(subsystem: "com.harbr.app", category: "SafeProcess")

    // MARK: Port check

    /// Returns true if something is accepting TCP connections on
    /// `localhost:port`. Tries IPv4 (127.0.0.1) then IPv6 (::1) so dev
    /// servers that bind to only one stack still register as running —
    /// modern Vite and several Node setups default to IPv6-only on
    /// localhost, which used to read as "stopped" in Harbr even though
    /// the browser could reach them just fine. Native BSD socket — no
    /// subprocess, no fork, safe under memory pressure.
    static func isPortActive(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }
        return tryConnect(port: port, family: AF_INET)
            || tryConnect(port: port, family: AF_INET6)
    }

    /// Non-blocking TCP connect to loopback on the requested family.
    /// 250ms poll matches the prior behavior — worst case for a port with
    /// no listener on either stack is ~500ms total.
    private static func tryConnect(port: Int, family: Int32) -> Bool {
        let sock = socket(family, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let connectResult: Int32
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        } else {
            var addr6 = sockaddr_in6()
            addr6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr6.sin6_family = sa_family_t(AF_INET6)
            addr6.sin6_port = UInt16(port).bigEndian
            // in6addr_loopback isn't directly importable in Swift, so
            // synthesize ::1 via inet_pton.
            _ = "::1".withCString { inet_pton(AF_INET6, $0, &addr6.sin6_addr) }
            connectResult = withUnsafePointer(to: &addr6) { ptr -> Int32 in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }

        if connectResult == 0 {
            return true
        }
        if errno != EINPROGRESS {
            return false  // immediate failure (likely ECONNREFUSED)
        }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, 250)
        guard pollResult > 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        let sockoptResult = getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &len)
        return sockoptResult == 0 && soError == 0
    }

    // MARK: Subprocess

    struct RunResult {
        let stdout: String
        let exitCode: Int32
    }

    /// Runs a subprocess and captures stdout. Returns nil if the launch
    /// or wait raises any kind of error (Swift error OR ObjC exception).
    static func runCapturingOutput(
        launchPath: String,
        arguments: [String],
        timeout: TimeInterval = 10
    ) -> RunResult? {
        var captured: RunResult?
        var caughtError: NSError?

        let ranWithoutException = HarbrSafeTry(&caughtError) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: launchPath)
            task.arguments = arguments

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            // Signal exit via terminationHandler instead of parking a GCD worker
            // on task.waitUntilExit(). The previous pattern (dispatch a utility
            // thread to call waitUntilExit, then group.wait on the caller) leaked
            // a worker every time waitUntilExit failed to return — which happens
            // when SIGTERM is ignored or CFRunLoop inside waitUntilExit misses
            // SIGCHLD. After enough leaks the 64-thread soft limit is reached and
            // the whole app stalls (AppKit needs GCD for sheet presentation, so
            // clicking the … browse button just spins the beachball).
            let exited = DispatchSemaphore(value: 0)
            task.terminationHandler = { _ in exited.signal() }

            do {
                try task.run()
            } catch {
                log.error("\(launchPath, privacy: .public) failed to launch: \(error.localizedDescription, privacy: .public)")
                return
            }

            if exited.wait(timeout: .now() + timeout) == .timedOut {
                log.error("\(launchPath, privacy: .public) timed out after \(timeout)s, terminating")
                task.terminate()
                if exited.wait(timeout: .now() + 1.0) == .timedOut {
                    // SIGTERM ignored — escalate. lsof/docker children can sit
                    // in uninterruptible kernel waits where SIGKILL still works.
                    let pid = task.processIdentifier
                    if pid > 0 { kill(pid, SIGKILL) }
                    _ = exited.wait(timeout: .now() + 1.0)
                }
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            captured = RunResult(stdout: output, exitCode: task.terminationStatus)
        }

        if !ranWithoutException, let caughtError {
            log.error("\(launchPath, privacy: .public) raised ObjC exception: \(caughtError.localizedDescription, privacy: .public)")
        }
        return captured
    }

    /// Fire-and-forget subprocess invocation that synchronously waits for exit
    /// but ignores output. Safe against ObjC exceptions and Swift errors.
    @discardableResult
    static func runWaitingForExit(launchPath: String, arguments: [String]) -> Bool {
        var ok = false
        var caughtError: NSError?

        let ranWithoutException = HarbrSafeTry(&caughtError) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: launchPath)
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                ok = true
            } catch {
                log.error("\(launchPath, privacy: .public) failed to launch: \(error.localizedDescription, privacy: .public)")
            }
        }

        if !ranWithoutException, let caughtError {
            log.error("\(launchPath, privacy: .public) raised ObjC exception: \(caughtError.localizedDescription, privacy: .public)")
        }
        return ok && ranWithoutException
    }
}
