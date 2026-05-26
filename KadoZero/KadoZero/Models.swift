//
//  Models.swift
//  KadoZero
//

import Foundation

// MARK: - リクエスト（アプリ → サーバーに送るデータ）

struct LoginRequest: Codable {
    let email: String
    let password: String
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case deviceID = "device_id"
    }
}

struct SignupRequest: Codable {
    let email: String
    let password: String
    let displayName: String
    let handle: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case displayName = "display_name"
        case handle
    }
}

struct AnalyzeRequest: Codable {
    let messageId: String
    let conversationId: String
    let text: String
    let tonePreference: String
    let language: String
    let recentMessages: [String]
    
    // SwiftのcamelCaseとJSONのsnake_caseを対応させる
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case text
        case tonePreference = "tone_preference"
        case language
        case recentMessages = "recent_messages"
    }
}

// MARK: - レスポンス（サーバー → アプリに返ってくるデータ）

struct AnalyzeResponse: Codable, Identifiable {
    let messageId: String
    let shouldReview: Bool
    let severity: String
    let emotion: String
    let detectedExpressions: [String]
    let originalText: String
    let suggestedText: String
    let reasons: [String]
    let analysisSummary: String

    var id: String { messageId }
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case shouldReview = "should_review"
        case severity
        case emotion
        case detectedExpressions = "detected_expressions"
        case originalText = "original_text"
        case suggestedText = "suggested_text"
        case reasons
        case analysisSummary = "analysis_summary"
    }
}

// MARK: - 認証 / ユーザ

struct MeResponse: Codable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let email: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case email
    }
}

struct AuthResponse: Codable {
    let user: MeResponse
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - 会話一覧

struct ConversationSummary: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String?
    let lastMessage: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
    }
}
