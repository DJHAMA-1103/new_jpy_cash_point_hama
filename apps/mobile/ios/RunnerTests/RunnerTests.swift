import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testCooldownAndClockRollback() {
    XCTAssertFalse(PointArrivalPolicy.isCoolingDown(last: nil, now: 1000))
    XCTAssertTrue(PointArrivalPolicy.isCoolingDown(last: 1000, now: 1599))
    XCTAssertFalse(PointArrivalPolicy.isCoolingDown(last: 1000, now: 1600))
    XCTAssertFalse(PointArrivalPolicy.isCoolingDown(last: 1000, now: 900))
  }

}
