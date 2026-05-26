//
//  KadoZeroTests.swift
//  KadoZeroTests
//

import Foundation
import Testing
@testable import KadoZero

private struct AnalyzerStub: MessageAnalyzing {
    let result: Result<AnalyzeResponse, Error>

    func analyzeMessage(text: String, recentMessages: [String]) async throws -> AnalyzeResponse {
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
struct KadoZeroTests {

    @Test func sendMessage_空文字は追加されない() {
        let viewModel = ChatViewModel(analyzer: AnalyzerStub(result: .failure(APIClientError.invalidResponse)))
        viewModel.inputText = "   \n"

        viewModel.sendMessage()

        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendMessage_送信直後に変換中メッセージが追加される() {
        let response = AnalyzeResponse(
            messageId: "msg_0",
            shouldReview: false,
            severity: "low",
            emotion: "neutral",
            detectedExpressions: [],
            originalText: "こんにちは",
            suggestedText: "こんにちは",
            reasons: [],
            analysisSummary: "問題なし"
        )
        let viewModel = ChatViewModel(analyzer: AnalyzerStub(result: .success(response)))
        viewModel.inputText = "こんにちは"

        viewModel.sendMessage()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].text == "こんにちは")
        #expect(viewModel.messages[0].isUser)
        #expect(viewModel.messages[0].isConverting)
    }

    @Test func sendMessage_成功時に同一バブルが変換完了する() async {
        let response = AnalyzeResponse(
            messageId: "msg_1",
            shouldReview: false,
            severity: "low",
            emotion: "neutral",
            detectedExpressions: [],
            originalText: "こんにちは",
            suggestedText: "こんにちは。よろしくお願いします。",
            reasons: [],
            analysisSummary: "問題なし"
        )
        let viewModel = ChatViewModel(analyzer: AnalyzerStub(result: .success(response)))
        viewModel.inputText = "こんにちは"

        viewModel.sendMessage()
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].isUser)
        #expect(viewModel.messages[0].text == "こんにちは。よろしくお願いします。")
        #expect(!viewModel.messages[0].isConverting)
    }

    @Test func sendMessage_レビュー必要フラグでも提案文へ更新する() async {
        let response = AnalyzeResponse(
            messageId: "msg_2",
            shouldReview: true,
            severity: "high",
            emotion: "anger",
            detectedExpressions: ["きつい"],
            originalText: "おい",
            suggestedText: "急ぎですが、対応状況を教えてください。",
            reasons: ["表現が強い"],
            analysisSummary: "送信前レビュー推奨"
        )
        let viewModel = ChatViewModel(analyzer: AnalyzerStub(result: .success(response)))
        viewModel.inputText = "おい"

        viewModel.sendMessage()
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages[0].text == "急ぎですが、対応状況を教えてください。")
        #expect(viewModel.messages[0].isUser)
        #expect(!viewModel.messages[0].isConverting)
    }

    @Test func sendMessage_API失敗時にエラー返信が追加される() async {
        let viewModel = ChatViewModel(analyzer: AnalyzerStub(result: .failure(APIClientError.invalidResponse)))
        viewModel.inputText = "こんにちは"

        viewModel.sendMessage()
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(viewModel.messages.count == 2)
        #expect(viewModel.messages[0].text == "こんにちは")
        #expect(viewModel.messages[0].isUser)
        #expect(!viewModel.messages[0].isConverting)
        #expect(viewModel.messages[1].text == "通信に失敗しました。時間をおいて再送してください。")
        #expect(!viewModel.messages[1].isUser)
        #expect(viewModel.errorMessage != nil)
    }
}



