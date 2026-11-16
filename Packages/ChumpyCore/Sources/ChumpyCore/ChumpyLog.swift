import Foundation

/// A small in-memory ring buffer of tunnel log lines, mirrored into the
/// shared UserDefaults so the app can display the core log on the Stats tab.
///
/// The tunnel extension and the app run in separate processes, so the
/// mirror is the transport: every appended line is persisted (batched
/// writes keep it cheap). The last `capacity` lines are kept.
///
/// Reading re-syncs with the mirror, so the app sees the tunnel's fresh
/// lines live. Clearing stamps a generation: a process still holding an
/// older buffer drops it at its next flush — a clear from one process
/// sticks in the other.
public final class ChumpyLog: @unchecked Sendable {

    public static let shared = ChumpyLog()

    private let lock = NSLock()
    private var lines: [String] = []
    /// How many of `lines` the mirror already holds — the rest is this
    /// process's unflushed tail.
    private var flushedCount = 0
    private var dirtyCount = 0
    /// The generation this instance last saw in the mirror — a clear
    /// stamps a newer one, and a stale buffer dies at the next flush.
    private var generation: Double
    private let capacity: Int
    private let flushEvery: Int

    public init(capacity: Int = 400, flushEvery: Int = 8) {
        self.capacity = capacity
        self.flushEvery = flushEvery
        generation = ChumpyConstant.sharedDefaults.double(forKey: Self.generationKey)
        lines = ChumpyConstant.sharedDefaults.stringArray(forKey: Self.storageKey) ?? []
        flushedCount = lines.count
    }

    private static let storageKey = "chumpy.tunnel.logBuffer"
    private static let generationKey = "chumpy.tunnel.logGeneration"

    /// Appends a line (timestamped) and periodically mirrors to shared defaults.
    public func append(_ line: String) {
        let trimmed = line.count > 2000 ? String(line.prefix(2000)) : line
        let stamp = Self.timeFormatter.string(from: Date())
        let defaults = ChumpyConstant.sharedDefaults

        lock.lock()
        lines.append("\(stamp) \(trimmed)")
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
            flushedCount = min(flushedCount, lines.count)
        }
        dirtyCount += 1
        if dirtyCount >= flushEvery {
            dirtyCount = 0
            // Another process may have cleared the mirror since our last
            // flush — a newer generation means our flushed head is stale
            // and dies here; only the fresh tail persists.
            let currentGeneration = defaults.double(forKey: Self.generationKey)
            if currentGeneration != generation {
                generation = currentGeneration
                if flushedCount > 0 {
                    lines.removeFirst(min(flushedCount, lines.count))
                    flushedCount = 0
                }
            }
            defaults.set(lines, forKey: Self.storageKey)
            flushedCount = lines.count
        }
        lock.unlock()
    }

    /// All currently buffered lines (newest last). The mirror is the
    /// transport between processes — it is re-read every time, so the
    /// app sees the tunnel's fresh lines, and this process's own
    /// unflushed tail rides along after them.
    public var all: [String] {
        lock.lock()
        let tail = flushedCount < lines.count ? Array(lines[flushedCount...]) : []
        lock.unlock()
        let persisted = ChumpyConstant.sharedDefaults.stringArray(forKey: Self.storageKey) ?? []
        return persisted + tail
    }

    /// Empties the buffer. A new generation is stamped so a process
    /// still holding an older buffer drops it at its next flush — the
    /// clear sticks across processes.
    public func clear() {
        let defaults = ChumpyConstant.sharedDefaults
        lock.lock()
        lines.removeAll()
        flushedCount = 0
        dirtyCount = 0
        generation = Date().timeIntervalSince1970
        lock.unlock()
        defaults.set(generation, forKey: Self.generationKey)
        defaults.removeObject(forKey: Self.storageKey)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
