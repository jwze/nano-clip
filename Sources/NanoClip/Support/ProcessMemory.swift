import AppKit
import Darwin

enum ProcessMemory {
    /// Resident set size of this process, used by `--diagnostics` and the README's memory budget.
    static var residentBytes: Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }

    static var residentDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(residentBytes), countStyle: .memory)
    }
}