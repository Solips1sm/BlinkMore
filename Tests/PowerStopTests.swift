@main enum PowerStopTests {
    static func main() {
        var stops = PowerStopPolicy()
        precondition(stops.request(100))
        precondition(!stops.request(100))
        precondition(!stops.complete(100, onAC: true, terminated: false))
        precondition(!stops.complete(100, onAC: false, terminated: false))
        precondition(stops.request(100))
        precondition(stops.complete(100, onAC: false, terminated: false))
        precondition(stops.request(101))
        precondition(!stops.complete(101, onAC: false, terminated: true))
        precondition(stops.request(102) && stops.request(103))
        precondition(!stops.complete(102, onAC: true, terminated: false))
        precondition(stops.complete(103, onAC: false, terminated: false))
        print("AC stop policy passed: reconnect cancels forced kill, duplicate checks, terminated processes and independent requests")
    }
}
