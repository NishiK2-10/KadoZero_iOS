//
//  KadoZeroUITests.swift
//  KadoZeroUITests
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import XCTest

final class KadoZeroUITests: XCTestCase {

    override func setUpWithError() throws {
        // セットアップ処理を実行
        // 各テストメソッド実行前に呼び出し

        // 失敗時の即停止を設定
        continueAfterFailure = false

        // テスト開始前の初期状態を設定（画面向きなど）
    }

    override func tearDownWithError() throws {
        // クリーンアップ処理を実行
        // 各テストメソッド実行後に呼び出し
    }

    @MainActor
    func testExample() throws {
        // UIテスト対象アプリを起動
        let app = XCUIApplication()
        app.launch()

        // XCTAssert で結果を検証
    }

    @MainActor
    func testLaunchPerformance() throws {
        // アプリ起動時間を計測
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
