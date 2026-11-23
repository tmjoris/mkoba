import XCTest

extension XCUIApplication {
    /// SwiftUI lists only build the rows on screen, so swipe until the element is there.
    @MainActor
    func scrolledTo(_ element: XCUIElement, maxSwipes: Int = 6) -> XCUIElement {
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            swipeUp()
            swipes += 1
        }
        return element
    }
}
