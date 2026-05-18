//
//  Models.swift
//  KadoZero
//

import Foundation

// MARK: - リクエスト（アプリ → サーバーに送るデータ）

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
