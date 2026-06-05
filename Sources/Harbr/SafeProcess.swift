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
    /// `127.0.0.1:port`. Native BSD socket — no subprocess, no fork,
    /// safe under memory pressure. Replaces the old `lsof -i :PORT`
    /// invocation, which crashed under memory pressure when the
    /// subprocess launch failed.
    static func isPortActive(_ port: Int) -> Bool {
        guard (1...65535).contains(port) else { return false }

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Non-blocking connect so we don't hang if the kernel queues SYN-RETRY.
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true  // connected immediately
        }
        if errno != EINPROGRESS {
            return false  // immediate failure (likely ECONNREFUSED)
        }

        // Wait briefly for the connect to complete.
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, 250)  // 250ms timeout
        guard pollResult > 0 else { return false }

        // Check whether the connect succeeded.
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

            do {
                try task.run()
            } catch {
                log.error("\(launchPath, privacy: .public) failed to launch: \(error.localizedDescription, privacy: .public)")
                return
            }

            // Wait with a timeout so a hung subprocess can't block the caller.
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                task.waitUntilExit()
                group.leave()
            }
            if group.wait(timeout: .now() + timeout) == .timedOut {
                log.error("\(launchPath, privacy: .public) timed out after \(timeout)s, terminating")
                task.terminate()
                _ = group.wait(timeout: .now() + 1.0)
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
