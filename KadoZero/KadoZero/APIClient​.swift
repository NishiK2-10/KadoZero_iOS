//
//  APIClient​.swift
//  KadoZero
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import Foundation

final class APIClient {
    private let baseURL = "http://localhost:8000"

    func analyzeMessage(text: String, recentMessages: [String]) async throws -> AnalyzeResponse {
        guard let url = URL(string: "\(baseURL)/v1/messages/analyze") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AnalyzeRequest(
            messageId: UUID().uuidString,
            conversationId: "conv_001",
            text: text,
            tonePreference: "gentle",
            language: "ja",
            recentMessages: recentMessages
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIClientError.httpStatus(code: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(AnalyzeResponse.self, from: data)
    }
}

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API URLが不正です。"
        case .invalidResponse:
            return "サーバー応答を解釈できませんでした。"
        case .httpStatus(let code):
            return "サーバーエラーが発生しました。(HTTP \(code))"
        }
    }
}
