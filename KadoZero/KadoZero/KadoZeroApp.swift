//
//  KadoZeroApp.swift
//  KadoZero
//
//  Created by 西岡裕斗 on 2026/04/21.
//

import SwiftUI

@main
struct KadoZeroApp: App {
    @State private var session = AuthSessionStore()

    var body: some Scene {
        WindowGroup {
            LaunchView(session: session)
        }
    }
}
