import XCTest
@testable import FortDocs

final class SearchViewModelTests: XCTestCase {
    func testPredicateWithSpecialCharacters() {
        let vm = SearchViewModel()
        let predicate = vm.buildTextSearchPredicate(query: "invoice(2024)")
        XCTAssertNotNil(predicate)
    }
}
