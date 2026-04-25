//
//  ContentView.swift
//  KadoZero
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("KadoZero")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("誰も傷つけない\n世界一優しいチャットアプリ")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
