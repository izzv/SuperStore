//
//  UITests.swift
//  UITests
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//
import XCTest
import Foundation

final class UITests: XCTestCase {
    private static let springboard_app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private static let spotlight_app = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    private static let searchBar = spotlight_app.textFields["SpotlightSearchField"]

    private static let APP_NAME = "SuperStore"
    func printAllMethods(of className: String) {
        guard let cls: AnyClass = objc_getClass(className) as? AnyClass else {
            print("Class \(className) not found")
            return
        }

        var methodCount: UInt32 = 0
        if let methodList = class_copyMethodList(cls, &methodCount) {
            for i in 0..<Int(methodCount) {
                let method = methodList[i]
                let sel = method_getName(method)
                print(String(describing: sel))
            }
            free(methodList)
        }
    }
    override func setUpWithError() throws {
        if !Self.mockIdlingPrivateApiToNoOp {
            let original = class_getInstanceMethod(
                objc_getClass("XCUIApplicationProcess") as? AnyClass,
                Selector(("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:"))
            )
            let replaced = class_getInstanceMethod(type(of: self), #selector(Self.replace))
            if let original, let replaced{
                method_exchangeImplementations(original, replaced)
            }
            Self.mockIdlingPrivateApiToNoOp = true
        }

        Self.deleteMyApp2()

        continueAfterFailure = false
    }
    override func tearDownWithError() throws {
        super.tearDown()
    }

    func testBulkAddRecommendedSources() throws {
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        let allowButton = systemAlert.scrollViews.otherElements.buttons["Allow"]
        _ = allowButton.exists || allowButton.waitForExistence(timeout: 0.5)
        allowButton.tap()
        try performBulkAddingRecommendedSources(for: app)
    }
    func testBulkAddInputSources() throws {

        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        let allowButton = systemAlert.scrollViews.otherElements.buttons["Allow"]
        _ = allowButton.exists || allowButton.waitForExistence(timeout: 0.5)
        allowButton.tap()

        try performBulkAddingInputSources(for: app)
    }

    func testRepeatabilityForStagingInputSources() throws {
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        let allowButton = systemAlert.scrollViews.otherElements.buttons["Allow"]
        _ = allowButton.exists || allowButton.waitForExistence(timeout: 0.5)
        allowButton.tap()

        try performRepeatabilityForStagingInputSources(for: app)
    }

    func testRepeatabilityForStagingRecommendedSources() throws {
        let app = XCUIApplication()
        app.launch()

        let systemAlert = Self.springboard_app.alerts["“\(Self.APP_NAME)” Would Like to Send You Notifications"]

        XCTAssertTrue(systemAlert.exists || systemAlert.waitForExistence(timeout: 5), "Notifications alert did not appear")
        let allowButton = systemAlert.scrollViews.otherElements.buttons["Allow"]
        _ = allowButton.exists || allowButton.waitForExistence(timeout: 0.5)
        allowButton.tap()

        try performRepeatabilityForStagingRecommendedSources(for: app)
    }

}

private extension UITests {
    class func dismissSpotlight(){
        if searchBar.exists {
            let clearButton = searchBar.buttons["Clear text"]
            if clearButton.exists{
                clearButton.tap()
            }
        }
        springboard_app.tap()
    }
    class func deleteMyApp() {
        XCUIApplication().terminate()
        dismissSpringboardAlerts()

        springboard_app.swipeDown()
        let searchBar = Self.searchBar
        _ = searchBar.exists || searchBar.waitForExistence(timeout: 5)
        searchBar.typeText(APP_NAME)

        let appIcon = spotlight_app.icons[APP_NAME]
        if appIcon.exists || appIcon.waitForExistence(timeout: 5) {
            appIcon.press(forDuration: 1)
            let deleteAppButton = spotlight_app.buttons["Delete App"]
            _ = deleteAppButton.exists || deleteAppButton.waitForExistence(timeout: 5)
            deleteAppButton.tap()
            let confirmDeleteButton = springboard_app.alerts["Delete “\(APP_NAME)”?"]
            _ = confirmDeleteButton.exists || confirmDeleteButton.waitForExistence(timeout: 5)
            confirmDeleteButton.scrollViews.otherElements.buttons["Delete"].tap()
        }
        let clearButton = searchBar.buttons["Clear text"]
        _ = clearButton.exists || clearButton.waitForExistence(timeout: 5)
        clearButton.tap()
        springboard_app.tap()
    }
    @objc func replace() {
        return
    }
    static var mockIdlingPrivateApiToNoOp = false

    class func deleteMyApp2() {
        XCUIApplication().terminate()
        dismissSpringboardAlerts()
        let appIcon = springboard_app.icons[APP_NAME]
        if appIcon.exists || appIcon.waitForExistence(timeout: 5) {
            appIcon.press(forDuration: 1)
            do {
                let button = springboard_app.buttons["Remove App"]
                _ = button.exists || button.waitForExistence(timeout: 5)
                button.tap()
                _ = springboard_app.waitForExistence(timeout: 0.5)
            }
            do {
                let button = springboard_app.buttons["Delete App"]
                _ = button.waitForExistence(timeout: 0.5)
                button.tap()
                _ = springboard_app.waitForExistence(timeout: 0.5)
            }
            do {
                let button = springboard_app.buttons["Delete"]
                _ = button.waitForExistence(timeout: 0.5)
                button.tap()
                _ = springboard_app.waitForExistence(timeout: 0.5)
            }

        }
    }
    class func dismissSpringboardAlerts() {
        for alert in springboard_app.alerts.allElementsBoundByIndex {
            if alert.exists {
                if alert.buttons["Cancel"].exists {
                    alert.buttons["Cancel"].tap()
                } else if let firstButton = alert.buttons.allElementsBoundByIndex.first {
                    firstButton.tap()
                }
            }
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = 6364136223846793005 &* seed &+ 1
        return seed
    }
}

private extension UITests {
    private func performBulkAdd(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery
    ) throws {
        try tapAddForThesePickedSources(app: app, sourceMappings: sourceMappings, cellsQuery: cellsQuery)
        let doneButton = app.navigationBars["Add Source"].buttons["Done"]
        _ = doneButton.waitForExistence(timeout: 0.5)
        doneButton.tap()
        for source in sourceMappings {
            let alertIdentifier = "Would you like to add the source “\(source.alertTitle)”?"
            let addSourceButton = app.alerts[alertIdentifier]
                .scrollViews.otherElements.buttons["Add Source"]
            _ = addSourceButton.waitForExistence(timeout: 0.5)
            addSourceButton.tap()
        }
    }
    private func performBulkAddingRecommendedSources(for app: XCUIApplication) throws {
        let srcTab = app.tabBars["Tab Bar"].buttons["Sources"]
        _ =  srcTab.waitForExistence(timeout: 0.5)
        srcTab.tap()
        let srcAdd = app.navigationBars["Sources"].buttons["Add"]
        _ = srcAdd.waitForExistence(timeout: 0.5)
        srcAdd.tap()

        let cellsQuery = app.collectionViews.cells
        let recommendedSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("SuperStore Team Picks\ncommunity-apps.sidestore.io/sidecommunity.json", "SuperStore Team Picks", false),
            ("Provenance EMU\nprovenance-emu.com/apps.json", "Provenance EMU", false),
            ("Countdown Respository\nneoarz.github.io/Countdown-App/Countdown.json", "Countdown Respository", false),
            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", true),
            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", false),
            ("Flyinghead\nflyinghead.github.io/flycast-builds/altstore.json", "Flyinghead", false),

            ("PokeMMO\npokemmo.eu/altstore/", "PokeMMO", true),
            ("Odyssey\ntheodyssey.dev/altstore/odysseysource.json", "Odyssey", false),
            ("Yattee\nrepos.yattee.stream/alt/apps.json", "Yattee", false),
            ("ThatStella7922 Source\nThe home for all apps ThatStella7922", "ThatStella7922 Source", false)
        ]
        try performBulkAdd(app: app, sourceMappings: recommendedSources, cellsQuery: cellsQuery)
    }

    private func performBulkAddingInputSources(for app: XCUIApplication) throws {
        UIPasteboard.general.string = """
            https://alts.lao.sb
            https://taurine.app/altstore/taurinestore.json
            https://randomblock1.com/altstore/apps.json
            https://burritosoftware.github.io/altstore/channels/burritosource.json
            https://bit.ly/40Isul6
            https://bit.ly/wuxuslibraryplus
            https://bit.ly/Quantumsource-plus
            https://bit.ly/Altstore-complete
            https://bit.ly/Quantumsource
        """.trimmedIndentation
        let srcTab = app.tabBars["Tab Bar"].buttons["Sources"]
        _ =  srcTab.waitForExistence(timeout: 0.5)
        srcTab.tap()
        let srcAdd = app.navigationBars["Sources"].buttons["Add"]
        _ = srcAdd.waitForExistence(timeout: 0.5)
        srcAdd.tap()

        let collectionViewsQuery = app.collectionViews
        let appsSidestoreIoTextField = collectionViewsQuery.textFields["apps.sidestore.io"]
        _ = appsSidestoreIoTextField.waitForExistence(timeout: 0.5)
        appsSidestoreIoTextField.tap()
        appsSidestoreIoTextField.tap()
        _ = appsSidestoreIoTextField.waitForExistence(timeout: 0.5)
        let pasteButton = collectionViewsQuery.staticTexts["Paste"]
        _ = pasteButton.waitForExistence(timeout: 0.5)
        pasteButton.tap()

        if app.keyboards.count > 0 {
            appsSidestoreIoTextField.typeText("\n") 
            _ =  app.exists || app.waitForExistence(timeout: 0.5)
        }
        let cellsQuery = collectionViewsQuery.cells

        let textInputSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("Laoalts\nalts.lao.sb", "Laoalts", false),
            ("Taurine\ntaurine.app/altstore/taurinestore.json", "Taurine", false),
            ("RandomSource\nrandomblock1.com/altstore/apps.json", "RandomSource", false),
            ("Burrito's AltStore\nburritosoftware.github.io/altstore/channels/burritosource.json", "Burrito's AltStore", true),
            ("Qn_'s AltStore Repo\nbit.ly/40Isul6", "Qn_'s AltStore Repo", false),
            ("WuXu's Library++\nThe Most Up-To-Date IPA Library on AltStore.", "WuXu's Library++", false),
            ("Quantum Source++\nContains tweaked apps, free streaming, cracked apps, and more.", "Quantum Source++", false),
            ("AltStore Complete\nContains tweaked apps, free streaming, cracked apps, and more.", "AltStore Complete", false),
            ("Quantum Source\nContains all of your favorite emulators, games, jailbreaks, utilities, and more.", "Quantum Source", false),
        ]
        try performBulkAdd(app: app, sourceMappings: textInputSources, cellsQuery: cellsQuery)
    }
    private func performRepeatabilityForStagingRecommendedSources(for app: XCUIApplication) throws {
        let srcTab = app.tabBars["Tab Bar"].buttons["Sources"]
        srcTab.tap()
        _ =  srcTab.waitForExistence(timeout: 0.5)
        let srcAdd = app.navigationBars["Sources"].buttons["Add"]
        srcAdd.tap()
        _ = srcAdd.waitForExistence(timeout: 0.5)

        let cellsQuery = app.collectionViews.cells
        let recommendedSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("SuperStore Team Picks\ncommunity-apps.sidestore.io/sidecommunity.json", "SuperStore Team Picks", false),
            ("Provenance EMU\nprovenance-emu.com/apps.json", "Provenance EMU", false),
            ("Countdown Respository\nneoarz.github.io/Countdown-App/Countdown.json", "Countdown Respository", false),
            ("OatmealDome's AltStore Source\naltstore.oatmealdome.me", "OatmealDome's AltStore Source", false),
            ("UTM Repository\nVirtual machines for iOS", "UTM Repository", false),
        ]
        let repeatCount = 3                                     
        let timeSeed = UInt64(Date().timeIntervalSince1970)     

        try repeatabilityTest(app: app, sourceMappings: recommendedSources, cellsQuery: cellsQuery, repeatCount: repeatCount, seed: timeSeed)
    }

    private func performRepeatabilityForStagingInputSources(for app: XCUIApplication) throws {
        UIPasteboard.general.string = """
            https://alts.lao.sb
            https://taurine.app/altstore/taurinestore.json
            https://randomblock1.com/altstore/apps.json
            https://burritosoftware.github.io/altstore/channels/burritosource.json
            https://bit.ly/40Isul6
        """.trimmedIndentation
        let srcTab = app.tabBars["Tab Bar"].buttons["Sources"]
        _ =  srcTab.waitForExistence(timeout: 0.5)
        srcTab.tap()
        let srcAdd = app.navigationBars["Sources"].buttons["Add"]
        _ = srcAdd.waitForExistence(timeout: 0.5)
        srcAdd.tap()

        let collectionViewsQuery = app.collectionViews
        let appsSidestoreIoTextField = collectionViewsQuery.textFields["apps.sidestore.io"]
        _ = appsSidestoreIoTextField.waitForExistence(timeout: 0.5)
        appsSidestoreIoTextField.tap()
        appsSidestoreIoTextField.tap()
        _ = appsSidestoreIoTextField.waitForExistence(timeout: 0.5)
        let pasteButton = collectionViewsQuery.staticTexts["Paste"]
        _ = pasteButton.waitForExistence(timeout: 0.5)
        pasteButton.tap()

        if app.keyboards.count > 0 {
            appsSidestoreIoTextField.typeText("\n") 
            _ =  app.exists || app.waitForExistence(timeout: 0.5)
        }
        let cellsQuery = collectionViewsQuery.cells

        let textInputSources: [(identifier: String, alertTitle: String, requiresSwipe: Bool)] = [
            ("Laoalts\nalts.lao.sb", "Laoalts", false),
            ("Taurine\ntaurine.app/altstore/taurinestore.json", "Taurine", false),
            ("RandomSource\nrandomblock1.com/altstore/apps.json", "RandomSource", false),
            ("Burrito's AltStore\nburritosoftware.github.io/altstore/channels/burritosource.json", "Burrito's AltStore", false),
            ("Qn_'s AltStore Repo\nbit.ly/40Isul6", "Qn_'s AltStore Repo", false),
        ]
        let repeatCount = 3                                     
        let timeSeed = UInt64(Date().timeIntervalSince1970)     

        try repeatabilityTest(app: app, sourceMappings: textInputSources, cellsQuery: cellsQuery, repeatCount: repeatCount, seed: timeSeed)
    }
    private func repeatabilityTest(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery,
        repeatCount: Int = 1,   
        seed: UInt64 = 42       
    ) throws {
        let seededGenerator = SeededGenerator(seed: seed)

        for _ in 0..<repeatCount {
            var seededGenerator = seededGenerator                                       

            let sourceMappings = sourceMappings.shuffled(using: &seededGenerator)       
            try tapAddForThesePickedSources(app: app, sourceMappings: sourceMappings, cellsQuery: cellsQuery)
        }
    }
    private func tapAddForThesePickedSources(
        app: XCUIApplication,
        sourceMappings: [(identifier: String, alertTitle: String, requiresSwipe: Bool)],
        cellsQuery: XCUIElementQuery
    ) throws {
        for source in sourceMappings {
            let sourceButton = cellsQuery.otherElements
                .containing(.button, identifier: source.identifier)
                .children(matching: .button)[source.identifier]
            XCTAssert(sourceButton.exists || sourceButton.waitForExistence(timeout: 10), "Source preview for id: '\(source.alertTitle)' not found in the view")

            _ =  sourceButton.exists || sourceButton.waitForExistence(timeout: 0.5)

            let addButton = sourceButton.children(matching: .button)["add"]
            XCTAssert(addButton.waitForExistence(timeout: 1))    

            let coord = addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coord.tap()
            if source.requiresSwipe {
                sourceButton.swipeUp(velocity: .slow)  
                _ = sourceButton.waitForExistence(timeout: 0.5)
            }
        }
    }
}

extension String {
    var trimmedIndentation: String {
        let lines = self.split(separator: "\n", omittingEmptySubsequences: false)
        let minIndent = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } 
            .map { $0.prefix { $0.isWhitespace }.count }
            .min() ?? 0
        return lines.map { line in
            String(line.dropFirst(minIndent))
        }.joined(separator: "\n")
    }
}
