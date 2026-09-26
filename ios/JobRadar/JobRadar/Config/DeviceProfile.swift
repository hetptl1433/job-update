import Foundation
import Metal
import os

/// What kind of device Orbit runs on and how much memory iOS lets it use.
/// Reads the hardware instead of `UIDevice`, so it works from any thread.
enum DeviceProfile {
    static let isPad: Bool = modelIdentifier.hasPrefix("iPad")

    /// "iPad" or "iPhone", for text such as "runs on this iPad".
    static var name: String { isPad ? "iPad" : "iPhone" }

    static var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// How fast this device's chip runs an on-device model.
    static let performance = DevicePerformance.estimate(
        gpuGeneration: gpuGeneration,
        isDesktopClass: isPad && ProcessInfo.processInfo.processorCount >= 8
    )

    /// Apple GPU generation from Metal: 7 is A14 or M1, 8 is A15, A16 or M2,
    /// 9 is A17 Pro, A18, M3 or M4, and 10 is A19 or M5. `nil` in the
    /// Simulator, whose GPU says nothing about the device it imitates.
    private static let gpuGeneration: Int? = {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        // Raw values keep this compiling against SDKs that don't name the
        // newest family yet; `apple7` is 1007.
        return (4...12).reversed().first { generation in
            guard let family = MTLGPUFamily(rawValue: 1000 + generation) else { return false }
            return device.supportsFamily(family)
        }
        #endif
    }()

    /// The most memory Orbit can use before iOS ends it: what Orbit uses now
    /// plus what it can still allocate. It reflects this device's per-app
    /// limit, including the raised limit from Orbit's increased-memory-limit
    /// entitlement. `nil` in the Simulator, which doesn't report a limit.
    static var appMemoryLimit: UInt64? {
        let available = UInt64(os_proc_available_memory())
        guard available > 0, let footprint = physicalFootprint else { return nil }
        return available + footprint
    }

    private static var physicalFootprint: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// For example "iPad16,5" or "iPhone15,4".
    private static let modelIdentifier: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }()
}

/// On-device model speed relative to an iPhone 15 (A16), the device the
/// model speeds in `LocalModelOption` were estimated for. Reading the prompt
/// is limited by GPU compute, writing the reply by memory bandwidth, so the
/// two scale separately. These are estimates until Orbit has measured a
/// model on the device itself.
struct DevicePerformance: Equatable, Sendable {
    var promptSpeed: Double
    var replySpeed: Double
    /// For example "A17 Pro/A18"; `nil` when the chip is unknown.
    var chipClass: String?

    static let reference = DevicePerformance(promptSpeed: 1, replySpeed: 1, chipClass: "A15/A16")

    /// M-series iPads have 8 or more CPU cores; A-series chips have 6.
    static func estimate(gpuGeneration: Int?, isDesktopClass: Bool) -> DevicePerformance {
        guard let generation = gpuGeneration else {
            return DevicePerformance(promptSpeed: 1, replySpeed: 1, chipClass: nil)
        }
        switch (generation, isDesktopClass) {
        case (...7, false): return DevicePerformance(promptSpeed: 0.75, replySpeed: 0.7, chipClass: "A14")
        case (8, false): return reference
        case (9, false): return DevicePerformance(promptSpeed: 1.3, replySpeed: 1.15, chipClass: "A17 Pro/A18")
        case (_, false): return DevicePerformance(promptSpeed: 1.8, replySpeed: 1.3, chipClass: "A19")
        case (...7, true): return DevicePerformance(promptSpeed: 1.4, replySpeed: 1.3, chipClass: "M1")
        case (8, true): return DevicePerformance(promptSpeed: 1.9, replySpeed: 1.9, chipClass: "M2")
        case (9, true): return DevicePerformance(promptSpeed: 2.3, replySpeed: 2.3, chipClass: "M3/M4")
        case (_, true): return DevicePerformance(promptSpeed: 4, replySpeed: 3, chipClass: "M5")
        }
    }
}
