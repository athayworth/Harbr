//
//  DockerStats.swift
//  Harbr
//
//  Copyright (c) 2025 Alexander Hayworth
//  Licensed under the MIT License. See LICENSE file for details.
//

import Foundation
import os

/// Pulls CPU + memory metrics for Docker containers so Harbr can display
/// real numbers for projects whose ports are held by Docker Desktop's
/// proxy rather than the actual app process.
///
/// Why this matters: when a user runs `docker run -p 5432:5432 postgres`,
/// macOS sees port 5432 as held by `com.docker.backend` (the proxy).
/// `ps -o %cpu,rss` for that PID reports a few hundred KB and ~0% CPU
/// regardless of what the container is actually doing, which makes
/// Harbr's verdicts and memory-warning threshold meaningless for the
/// Docker case. Asking the Docker CLI directly fixes that — `docker
/// stats` reads from the container runtime and reports real container
/// load.
///
/// The module is stateless: every call shells out to `docker`. The poll
/// loop bundles two calls per cycle (`docker ps` to learn the port→
/// container mapping, `docker stats` to read CPU/memory) regardless of
/// how many projects are docker-backed, so the cost stays bounded as
/// the project list grows. If Docker isn't installed or the daemon is
/// stopped both calls return empty results and the existing PS-based
/// path runs unchanged.
enum DockerStats {
    static let log = Logger(subsystem: "com.harbr.app", category: "DockerStats")

    struct Sample {
        let cpu: Double  // percent, summed across cores like ps's %cpu
        let memMB: Double
    }

    /// Returns CPU + memory samples keyed by the host port the container
    /// publishes them on. Empty map if Docker is unavailable, the daemon
    /// is down, no containers publish ports, OR we've recently seen Docker
    /// time out and are in cooldown.
    static func samplesByHostPort() -> [Int: Sample] {
        // Cooldown: when Docker Desktop hangs (memory pressure, restart,
        // daemon stall), every `docker ps` call sits at the 1s timeout
        // before failing. Across a 12-project config that already eats
        // 1s of the 5s poll budget every cycle, and consecutive failures
        // mean Harbr never gets to commit a fresh portStatusCache update
        // because the next poll's pollGeneration check discards the in-
        // flight one. Skipping Docker entirely for cooldownDuration after
        // consecutiveFailures hits the threshold lets the PS-based path
        // keep producing live state until Docker comes back.
        if Date() < cooldownUntil { return [:] }

        guard let portMap = portToContainerMap() else {
            recordFailure()
            return [:]
        }
        recordSuccess()
        if portMap.isEmpty { return [:] }

        let uniqueContainers = Array(Set(portMap.values))
        guard let containerSamples = statsForContainers(uniqueContainers) else {
            // `docker ps` worked but `docker stats` didn't — don't trip
            // the cooldown for this; the daemon's responsive enough for
            // listing, just possibly slow on stats. Next poll will retry.
            return [:]
        }
        if containerSamples.isEmpty { return [:] }

        var result: [Int: Sample] = [:]
        for (port, containerID) in portMap {
            if let sample = containerSamples[containerID] {
                result[port] = sample
            }
        }
        return result
    }

    // MARK: Cooldown state

    private static var consecutiveFailures: Int = 0
    private static var cooldownUntil: Date = .distantPast
    private static let maxConsecutiveFailures = 2
    private static let cooldownDuration: TimeInterval = 60

    private static func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures {
            cooldownUntil = Date().addingTimeInterval(cooldownDuration)
            log.info("Docker check failed \(consecutiveFailures) times in a row — skipping Docker for \(Int(cooldownDuration))s")
            // Don't keep growing the counter forever; the cooldown is
            // the actual rate-limit, the counter just gates entering it.
            consecutiveFailures = 0
        }
    }

    private static func recordSuccess() {
        consecutiveFailures = 0
    }

    // MARK: Internals

    /// Where Docker Desktop typically installs its CLI on macOS. Checked in
    /// order; the first executable hit wins. `/usr/local/bin/docker` is the
    /// classic location; `/opt/homebrew/bin/docker` covers Apple Silicon
    /// Homebrew; `/usr/bin/docker` covers system installs.
    private static let candidatePaths = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/usr/bin/docker"
    ]

    /// Resolved once per process. Recomputing every poll would add a stat()
    /// call for nothing — Docker doesn't move between installs while the
    /// app is running.
    private static let dockerPath: String? = {
        for p in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }()

    /// Reads `docker ps` and parses each row's Ports column for host-port
    /// mappings, returning `host_port → containerID`. Returns nil when the
    /// `docker ps` call itself failed (timeout, daemon down, docker not
    /// installed) so the caller can distinguish that case from a successful
    /// call that just found no containers — and trip the cooldown only on
    /// the former.
    private static func portToContainerMap() -> [Int: String]? {
        guard let dockerPath else { return nil }
        guard let result = SafeProcess.runCapturingOutput(
            launchPath: dockerPath,
            arguments: ["ps", "--format", "{{.ID}}\t{{.Ports}}"],
            timeout: 1
        ), result.exitCode == 0 else { return nil }

        var map: [Int: String] = [:]
        for line in result.stdout.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let containerID = parts[0].trimmingCharacters(in: .whitespaces)
            let portsField = parts[1]
            guard !containerID.isEmpty else { continue }
            for port in extractHostPorts(portsField) {
                map[port] = containerID
            }
        }
        return map
    }

    /// Reads `docker stats --no-stream` for the given containers in one
    /// call (Docker accepts multiple IDs as positional args) so we don't
    /// pay process-spawn overhead per container. Returns nil on call
    /// failure (caller treats it as "skip stats this poll" rather than
    /// "Docker is broken — cool it down").
    private static func statsForContainers(_ containerIDs: [String]) -> [String: Sample]? {
        guard let dockerPath, !containerIDs.isEmpty else { return [:] }
        guard let result = SafeProcess.runCapturingOutput(
            launchPath: dockerPath,
            arguments: ["stats", "--no-stream", "--format", "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}"] + containerIDs,
            timeout: 2
        ), result.exitCode == 0 else { return nil }

        var samples: [String: Sample] = [:]
        for line in result.stdout.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let cpuStr = parts[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "%", with: "")
            guard let cpu = Double(cpuStr), !id.isEmpty else { continue }
            guard let memMB = parseMemUsage(parts[2]) else { continue }
            samples[id] = Sample(cpu: cpu, memMB: memMB)
        }
        return samples
    }

    /// Parses host ports from Docker's Ports column. Each container may emit
    /// patterns like `0.0.0.0:5432->5432/tcp, :::5432->5432/tcp` (IPv4 + IPv6
    /// for the same publication), and the IPv4/IPv6 entries collapse to the
    /// same host port — using a Set dedupes them so the map doesn't churn.
    private static func extractHostPorts(_ portsField: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)->"#) else { return [] }
        let ns = portsField as NSString
        var seen: Set<Int> = []
        regex.enumerateMatches(in: portsField, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let portStr = ns.substring(with: match.range(at: 1))
            if let p = Int(portStr) { seen.insert(p) }
        }
        return Array(seen)
    }

    /// Parses Docker's MemUsage column ("150MiB / 2GiB") to a Double in MB.
    /// We only care about the used side — the limit is host-aware and not
    /// useful for ranking projects. Handles both IEC (MiB, GiB) and SI
    /// (MB, GB) units; Docker emits IEC by default but some configurations
    /// flip this and either is plausible.
    private static func parseMemUsage(_ s: String) -> Double? {
        let usage = s.components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespaces) ?? s
        let pattern = #"^([\d.]+)\s*([KMGT]i?B|B)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = usage as NSString
        guard let match = regex.firstMatch(in: usage, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }
        let valueStr = ns.substring(with: match.range(at: 1))
        let unit = ns.substring(with: match.range(at: 2)).uppercased()
        guard let value = Double(valueStr) else { return nil }
        switch unit {
        case "B": return value / (1024 * 1024)
        case "KIB", "KB": return value / 1024
        case "MIB", "MB": return value
        case "GIB", "GB": return value * 1024
        case "TIB", "TB": return value * 1024 * 1024
        default: return nil
        }
    }
}
