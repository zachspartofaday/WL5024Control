import Testing
@testable import WL5024Probe

struct ProbeExitStatusTests {
    @Test(arguments: [(1, 0, 1), (3, 2, 1), (3, 0, 3), (3, 2, 0)])
    func incompleteQueryRunFails(counts: (Int, Int, Int)) {
        #expect(ProbeExitStatus.completedQueries(
            requests: counts.0, responses: counts.1, timeouts: counts.2
        ) == 74)
    }

    @Test func everyQueryAnsweredSucceeds() {
        #expect(ProbeExitStatus.completedQueries(requests: 3, responses: 3, timeouts: 0) == 0)
    }
}
