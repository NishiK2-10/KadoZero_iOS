//
//  AppShell.swift
//  KadoZero
//

import Observation
import SwiftUI

@Observable
@MainActor
final class AuthSessionStore {
    enum SessionState {
        case launching
        case unauthenticated
        case authenticated
    }

    var state: SessionState = .launching
    var accessToken: String?
    var currentUser: MeResponse?
    var authErrorMessage: String?

    private let client = APIClient()

    func bootstrap() async {
        // 起動時は未認証として開始（次段でKeychain復元を追加）
        state = .unauthenticated
    }

    func login(email: String, password: String) async {
        authErrorMessage = nil
        do {
            let result = try await client.login(email: email, password: password, deviceID: "ios-device")
            accessToken = result.accessToken
            currentUser = result.user
            state = .authenticated
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func signup(email: String, password: String, displayName: String, handle: String) async {
        authErrorMessage = nil
        do {
            let result = try await client.signup(
                email: email,
                password: password,
                displayName: displayName,
                handle: handle
            )
            accessToken = result.accessToken
            currentUser = result.user
            state = .authenticated
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func logout() {
        accessToken = nil
        currentUser = nil
        state = .unauthenticated
    }
}

struct LaunchView: View {
    @Bindable var session: AuthSessionStore

    var body: some View {
        Group {
            switch session.state {
            case .launching:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("起動中...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .task {
                    await session.bootstrap()
                }
            case .unauthenticated:
                LoginView(session: session)
            case .authenticated:
                MainTabView(session: session)
            }
        }
    }
}

struct LoginView: View {
    @Bindable var session: AuthSessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    private var isDisabled: Bool {
        isSubmitting || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("KadoZero")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)

                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("パスワード", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let error = session.authErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        isSubmitting = true
                        await session.login(email: email, password: password)
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("ログイン")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)

                NavigationLink("新規登録はこちら") {
                    SignUpView(session: session)
                }
                .font(.footnote)

                Spacer()
            }
            .padding()
            .navigationTitle("ログイン")
        }
    }
}

struct SignUpView: View {
    @Bindable var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var handle = ""
    @State private var isSubmitting = false

    private var normalizedHandle: String {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            return trimmed
        }
        if trimmed.isEmpty {
            return trimmed
        }
        return "@\(trimmed)"
    }

    private var isDisabled: Bool {
        isSubmitting
        || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || password.count < 10
        || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || normalizedHandle.count < 2
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("表示名", text: $displayName)
                TextField("ハンドル（例: @yuto_n）", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                SecureField("パスワード（10文字以上）", text: $password)
            }

            Section {
                Button {
                    Task {
                        isSubmitting = true
                        await session.signup(
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            handle: normalizedHandle
                        )
                        isSubmitting = false
                        if session.state == .authenticated {
                            dismiss()
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("新規登録")
                    }
                }
                .disabled(isDisabled)
            }

            if let error = session.authErrorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("新規登録")
    }
}

struct MainTabView: View {
    @Bindable var session: AuthSessionStore

    var body: some View {
        TabView {
            ChatListView()
                .tabItem {
                    Label("チャット", systemImage: "message")
                }

            FriendListView()
                .tabItem {
                    Label("友だち", systemImage: "person.2")
                }

            SettingsView(session: session)
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

struct ChatListView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ContentView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("テスト会話")
                            .font(.headline)
                        Text("ここから通訳付きチャットを開始")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("チャット")
        }
    }
}

struct FriendListView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("友だち機能は次段で実装")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("友だち")
        }
    }
}

struct SettingsView: View {
    @Bindable var session: AuthSessionStore

    var body: some View {
        NavigationStack {
            List {
                Section("アカウント") {
                    if let me = session.currentUser {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(me.displayName)
                                .font(.headline)
                            Text(me.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("未ログイン")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button("ログアウト", role: .destructive) {
                        session.logout()
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}
