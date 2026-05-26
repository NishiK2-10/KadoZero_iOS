//
//  ConversationViewModel.swift
//  KadoZero
//

import Foundation
import Observation

@MainActor
@Observable
final class ConversationViewModel {
    var inputText = ""
    private(set) var messages: [ChatMessage] = []
    private(set) var isAnalyzing = false
    private(set) var errorMessage: String?

    private let accessToken: String
    private let conversationID: String
    private let currentUserID: String
    private let client: APIClient

    init(
        accessToken: String,
        conversationID: String,
        currentUserID: String,
        client: APIClient = APIClient()
    ) {
        self.accessToken = accessToken
        self.conversationID = conversationID
        self.currentUserID = currentUserID
        self.client = client
    }

    var isSendDisabled: Bool {
        isAnalyzing || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadMessages() async {
        do {
            let rows = try await client.fetchMessages(accessToken: accessToken, conversationID: conversationID)
            messages = rows.map {
                ChatMessage(
                    text: $0.body,
                    isUser: $0.senderId == currentUserID,
                    isConverting: false
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage() {
        let original = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !isAnalyzing else { return }
        inputText = ""
        errorMessage = nil

        let localID = UUID()
        messages.append(ChatMessage(id: localID, text: original, isUser: true, isConverting: true))

        Task {
            await analyzeAndSend(originalText: original, localMessageID: localID)
        }
    }

    private func analyzeAndSend(originalText: String, localMessageID: UUID) async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let recent = Array(messages.suffix(6).map(\.text))
            let analyzed = try await client.analyzeMessage(text: originalText, recentMessages: recent)
            let converted = analyzed.suggestedText

            _ = try await client.sendMessage(
                accessToken: accessToken,
                conversationID: conversationID,
                clientMessageID: UUID().uuidString,
                body: converted,
                originalBody: originalText
            )

            finalizeLocalMessage(localMessageID, convertedText: converted)
        } catch {
            errorMessage = error.localizedDescription
            finalizeLocalMessage(localMessageID, convertedText: originalText)
        }
    }

    private func finalizeLocalMessage(_ id: UUID, convertedText: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = convertedText
        messages[index].isConverting = false
    }
}

