//
//  APIClient​.swift
//  KadoZero
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import Foundation

class APIClient {
    
    // サーバのURL（仮置き）
    private let baseURL = "http://localhost:8000"
    
    // メッセージを分析するリクエストを送る
    func analyzeMessage(text: String) async throws -> AnalyzeResponse {
        // 1. URLを組み立てる
        let url = URL(string: "\(baseURL)/v1/messages/analyze")!
        
        // 2. リクエストを作る
        var request  = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 3. 送るデータを作る
        let body = AnalyzeRequest(
            messageId: UUID().uuidString,
            conversationId: "conv_001",
            text: text,
            tonePreference: "gentle",
            language: "ja",
            recentMessages: []
        )
        // 4. SwiftのstructをJSONに変換する
        request.httpBody = try JSONEncoder().encode(body)
        
        // 5. サーバに送って返事を待つ
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // 6. 返ってきたJSONをSwiftのstructに変換する
        let response  = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        
        return response
    }
}
