import XCTest
import Darwin

let suite = XCTestSuite(name: "Aero Core Regression Tests")
suite.addTest(XCTestSuite(forTestCaseClass: PolicyTests.self))
suite.addTest(XCTestSuite(forTestCaseClass: SessionStoreTests.self))
suite.run()
guard let result = suite.testRun, result.executionCount == 8 else {
    print("Expected eight regression tests to execute")
    exit(1)
}
exit(result.totalFailureCount == 0 ? 0 : 1)
