import XCTest
@testable import MyLib

final class MyLibTests: XCTestCase {
    func testAdd() {
        let lib = MyLib()
        XCTAssertEqual(lib.add(2, 3), 5)
    }
}
