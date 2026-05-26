//
//  APIClient​.swift
//  KadoZero
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import Foundation

final class APIClient {
    private let baseURL: String

    init(baseURL: String? = nil) {
        if let baseURL {
            self.baseURL = baseURL
            print("[APIClient] baseURL override: \(self.baseURL)")
            return
        }

        let mappedValue = Bundle.main.object(forInfoDictionaryKey: "KADOZERO_API_BASE_URL") as? String
        self.baseURL = mappedValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("[APIClient] resolved baseURL: \(self.baseURL)")
    }

    func analyzeMessage(text: String, recentMessages: [String]) async throws -> AnalyzeResponse {
        guard Self.isUsableURL(baseURL) else {
            throw APIClientError.missingOrInvalidBaseURL(baseURL)
        }

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

    func login(email: String, password: String, deviceID: String) async throws -> AuthResponse {
        guard Self.isUsableURL(baseURL) else {
            throw APIClientError.missingOrInvalidBaseURL(baseURL)
        }
        guard let url = URL(string: "\(baseURL)/v1/auth/login") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password, deviceID: deviceID))

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func signup(email: String, password: String, displayName: String, handle: String) async throws -> AuthResponse {
        guard Self.isUsableURL(baseURL) else {
            throw APIClientError.missingOrInvalidBaseURL(baseURL)
        }
        guard let url = URL(string: "\(baseURL)/v1/auth/signup") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SignupRequest(email: email, password: password, displayName: displayName, handle: handle)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func me(accessToken: String) async throws -> MeResponse {
        guard Self.isUsableURL(baseURL) else {
            throw APIClientError.missingOrInvalidBaseURL(baseURL)
        }
        guard let url = URL(string: "\(baseURL)/v1/auth/me") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)
        return try JSONDecoder().decode(MeResponse.self, from: data)
    }

    func fetchConversations(accessToken: String) async throws -> [ConversationSummary] {
        guard Self.isUsableURL(baseURL) else {
            throw APIClientError.missingOrInvalidBaseURL(baseURL)
        }
        guard let url = URL(string: "\(baseURL)/v1/conversations?limit=30") else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response)
        return try JSONDecoder().decode([ConversationSummary].self, from: data)
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIClientError.httpStatus(code: httpResponse.statusCode)
        }
    }

    private static func isUsableURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.contains("$(") { return false }
        if value == "http:" || value == "https:" { return false }
        guard let url = URL(string: value), let scheme = url.scheme else { return false }
        return scheme == "http" || scheme == "https"
    }
}

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(code: Int)
    case missingOrInvalidBaseURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "API URLが不正です。"
        case .invalidResponse:
            return "サーバー応答を解釈できませんでした。"
        case .httpStatus(let code):
            return "サーバーエラーが発生しました。(HTTP \(code))"
        case .missingOrInvalidBaseURL(let value):
            if value.isEmpty {
                return "KADOZERO_API_BASE_URL が未設定です。Info.plist と Build Settings を確認してください。"
            }
            return "KADOZERO_API_BASE_URL が不正です: \(value)"
        }
    }
}
