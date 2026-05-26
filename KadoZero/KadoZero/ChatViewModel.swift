//
//  ChatViewModel.swift
//  KadoZero
//

import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    let isUser: Bool
    var isConverting: Bool

    init(id: UUID = UUID(), text: String, isUser: Bool, isConverting: Bool = false) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.isConverting = isConverting
    }
}

protocol MessageAnalyzing {
    func analyzeMessage(text: String, recentMessages: [String]) async throws -> AnalyzeResponse
}

extension APIClient: MessageAnalyzing {}

@MainActor
@Observable
final class ChatViewModel {
    var inputText = ""
    private(set) var messages: [ChatMessage] = []
    private(set) var isAnalyzing = false
    private(set) var errorMessage: String?

    private let analyzer: MessageAnalyzing

    init(analyzer: MessageAnalyzing = APIClient()) {
        self.analyzer = analyzer
    }

    var isSendDisabled: Bool {
        isAnalyzing || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }

        errorMessage = nil
        inputText = ""
        let messageID = UUID()
        messages.append(ChatMessage(id: messageID, text: trimmed, isUser: true, isConverting: true))

        Task {
            await analyzeAndHandleReply(for: trimmed, messageID: messageID)
        }
    }

    private func analyzeAndHandleReply(for text: String, messageID: UUID) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let recentMessages = Array(messages.suffix(6).map(\.text))
            let response = try await analyzer.analyzeMessage(text: text, recentMessages: recentMessages)
            finalizeMessage(id: messageID, convertedText: response.suggestedText)
        } catch {
            print("[ChatViewModel] analyzeMessage error: \(error)")
            errorMessage = error.localizedDescription
            finalizeMessage(id: messageID, convertedText: text)
            messages.append(ChatMessage(text: "通信に失敗しました。時間をおいて再送してください。", isUser: false))
        }
    }

    private func finalizeMessage(id: UUID, convertedText: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = convertedText
        messages[index].isConverting = false
    }
}
