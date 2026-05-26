//
//  KadoZeroUITestsLaunchTests.swift
//  KadoZeroUITests
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import XCTest

final class KadoZeroUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // 起動後〜スクリーンショット前の手順を実行
        // 例: テスト用アカウントでログイン、特定画面へ遷移

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
