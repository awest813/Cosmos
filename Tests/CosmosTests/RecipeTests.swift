import XCTest
@testable import Cosmos

final class RecipeTests: XCTestCase {
    func testDisplayTitleUsesDescriptionWhenDistinct() {
        let recipe = RepairRecipe(id: "vcrun2019", kind: .dependency, description: "Visual C++ 2019")
        XCTAssertEqual(recipe.displayTitle, "Visual C++ 2019")
        XCTAssertEqual(recipe.displaySubtitle, "vcrun2019")
    }

    func testDisplayTitleHumanizesIDWhenNoDescription() {
        let recipe = RepairRecipe(id: "d3dcompiler_47", kind: .fix, description: "d3dcompiler_47")
        XCTAssertEqual(recipe.displayTitle, "d3dcompiler 47")
    }
}
