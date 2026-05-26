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
            ChatListView(session: session)
                .tabItem {
                    Label("チャット", systemImage: "message")
                }

            FriendListView(session: session)
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
    @Bindable var session: AuthSessionStore
    @State private var conversations: [ConversationSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let client = APIClient()

    private var accessToken: String? {
        session.accessToken
    }

    private var currentUserID: String? {
        session.currentUser?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("テスト") {
                    NavigationLink {
                        ContentView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("テストチャット")
                                .font(.headline)
                            Text("ローカル検証用（1件固定）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("トーク") {
                    ForEach(conversations) { conversation in
                        if let token = accessToken, let userID = currentUserID {
                            NavigationLink {
                                ConversationView(
                                    viewModel: ConversationViewModel(
                                        accessToken: token,
                                        conversationID: conversation.id,
                                        currentUserID: userID,
                                        onUnauthorized: { session.logout() }
                                    ),
                                    title: conversation.title ?? "会話"
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title ?? "会話")
                                        .font(.headline)
                                    Text(conversation.lastMessage ?? "メッセージはまだありません")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteConversation(conversationID: conversation.id) }
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("チャット")
            .overlay {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if conversations.isEmpty {
                    ContentUnavailableView("会話がありません", systemImage: "message")
                }
            }
            .task {
                await reload()
            }
            .refreshable {
                await reload()
            }
            .alert("エラー", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func reload() async {
        guard let token = accessToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await client.fetchConversations(accessToken: token)
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func deleteConversation(conversationID: String) async {
        guard let token = accessToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.deleteConversation(accessToken: token, conversationID: conversationID)
            conversations = try await client.fetchConversations(accessToken: token)
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct FriendListView: View {
    @Bindable var session: AuthSessionStore
    @State private var friends: [FriendSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeConversation: ConversationSummary?
    @State private var isStartingConversation = false
    @State private var isPresentingAddFriend = false
    @State private var friendUserIDInput = ""
    private let client = APIClient()

    var body: some View {
        NavigationStack {
            List(friends) { friend in
                Button {
                    Task { await startDM(with: friend) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(friend.displayName)
                            .font(.headline)
                        Text(friend.handle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .disabled(isStartingConversation)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await removeFriend(friendID: friend.id) }
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("友だち")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        friendUserIDInput = ""
                        isPresentingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("読み込み中...")
                } else if friends.isEmpty {
                    ContentUnavailableView("友だちがいません", systemImage: "person.2")
                }
            }
            .task {
                await loadFriends()
            }
            .refreshable {
                await loadFriends()
            }
            .navigationDestination(item: $activeConversation) { conversation in
                if let token = session.accessToken, let userID = session.currentUser?.id {
                    ConversationView(
                        viewModel: ConversationViewModel(
                            accessToken: token,
                            conversationID: conversation.id,
                            currentUserID: userID,
                            onUnauthorized: { session.logout() }
                        ),
                        title: conversation.title ?? "会話"
                    )
                } else {
                    Text("セッションが無効です")
                }
            }
            .alert("エラー", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $isPresentingAddFriend) {
                NavigationStack {
                    Form {
                        Section("友だちのユーザーID") {
                            TextField("例: cb726bc5-e15b-4444-ab81-c3a7d3b4e7dc", text: $friendUserIDInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .navigationTitle("友だち追加")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("キャンセル") {
                                isPresentingAddFriend = false
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("追加") {
                                Task { await addFriend() }
                            }
                            .disabled(friendUserIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func loadFriends() async {
        guard let token = session.accessToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await client.fetchFriends(accessToken: token)
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func startDM(with friend: FriendSummary) async {
        guard let token = session.accessToken else { return }
        isStartingConversation = true
        defer { isStartingConversation = false }
        do {
            let conversation = try await client.createConversation(
                accessToken: token,
                kind: "dm",
                memberIDs: [friend.id],
                title: friend.displayName
            )
            activeConversation = conversation
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func addFriend() async {
        guard let token = session.accessToken else { return }
        let userID = friendUserIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { return }
        do {
            _ = try await client.addFriend(accessToken: token, userID: userID)
            isPresentingAddFriend = false
            await loadFriends()
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func removeFriend(friendID: String) async {
        guard let token = session.accessToken else { return }
        do {
            try await client.removeFriend(accessToken: token, friendUserID: friendID)
            await loadFriends()
        } catch {
            if APIClientError.isUnauthorized(error) {
                session.logout()
                return
            }
            errorMessage = error.localizedDescription
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
                            Text(me.id)
                                .font(.caption2)
                                .foregroundColor(.secondary)
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
