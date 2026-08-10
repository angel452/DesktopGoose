import Foundation

/// A dependency-free test harness.
///
/// XCTest and swift-testing both ship with Xcode, not with the Command Line
/// Tools. Rather than demand a 35 GB install to assert on a state machine, the
/// suite runs as a plain executable: `swift run GooseCoreTests`.
final class TestRunner {
    private var passed = 0
    private var currentTest = ""
    private var failures: [String] = []

    func test(_ name: String, _ body: () -> Void) {
        currentTest = name
        let failuresBefore = failures.count

        body()

        if failures.count == failuresBefore {
            passed += 1
            print("  ok   \(name)")
        } else {
            print("  FAIL \(name)")
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: UInt = #line) {
        guard !condition else { return }
        failures.append("\(currentTest) (line \(line)): \(message())")
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "value", line: UInt = #line) {
        expect(actual == expected, "\(label): expected \(expected), got \(actual)", line: line)
    }

    func fail(_ message: String, line: UInt = #line) {
        failures.append("\(currentTest) (line \(line)): \(message)")
    }

    func finish() -> Never {
        print("")
        guard failures.isEmpty else {
            print("\(failures.count) failure(s):")
            for failure in failures { print("  - \(failure)") }
            exit(1)
        }
        print("\(passed) test(s) passed.")
        exit(0)
    }
}
