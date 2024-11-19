import XCTest
@testable import NeedleTailLogger

final class NeedletailLoggerTests: XCTestCase {
    let logger = NeedleTailLogger(writeToFile: true)
    
    func testWriteDebugLog() async {
        for _ in 0..<3000 {
            await logger.log(level: .debug, message: "DEBUG A LOG")
        }
    }
}
