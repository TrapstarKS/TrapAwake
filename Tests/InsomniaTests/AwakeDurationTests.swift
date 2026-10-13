import XCTest
@testable import Insomnia

final class AwakeDurationTests: XCTestCase {
    func testCustomDurationAcceptsFiniteMinutesWithinCoreLimits() {
        XCTAssertEqual(AwakeDuration.minutes(" 1 "), 60)
        XCTAssertEqual(AwakeDuration.minutes("1.5"), 90)
        XCTAssertEqual(AwakeDuration.minutes("43200"), AwakePreferences.maximumDuration)
    }

    func testCustomDurationRejectsInvalidAndOutOfRangeInput() {
        for input in ["", "abc", "nan", "inf", "-1", "0", "0.99", "43200.01"] {
            XCTAssertNil(AwakeDuration.minutes(input), input)
        }
    }

    func testCountdownRoundsUpAndClampsExpiredSessions() {
        XCTAssertEqual(AwakeDuration.countdown(60.1), "1:01")
        XCTAssertEqual(AwakeDuration.countdown(3661), "1:01:01")
        XCTAssertEqual(AwakeDuration.countdown(-0.5), "0:00")
    }
}
