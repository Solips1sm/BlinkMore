struct PowerStopPolicy {
    private var pending: Set<Int32> = []

    mutating func request(_ pid: Int32) -> Bool { pending.insert(pid).inserted }

    mutating func complete(_ pid: Int32, onAC: Bool, terminated: Bool) -> Bool {
        let requested = pending.remove(pid) != nil
        return requested && !onAC && !terminated
    }
}
