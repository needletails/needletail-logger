import XCTest
@testable import NeedleTailLogger

final class NeedletailLoggerTests: XCTestCase {
    let logger = NeedleTailLogger()
    
    func testWriteDebugLog() {
        logger.log(level: .debug, message: "DEBUG A LOG")
    }
}
