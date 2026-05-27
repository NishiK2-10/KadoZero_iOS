//
//  ConversationView.swift
//  KadoZero
//

import SwiftUI

struct ConversationView: View {
    @State var viewModel: ConversationViewModel
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            if viewModel.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("AIが文面を確認中...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                TextField("メッセージを入力", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)

                Button(action: viewModel.sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.isSendDisabled)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMessages()
        }
    }
}

#Preview {
    NavigationStack {
        ConversationView(
            viewModel: ConversationViewModel(
                accessToken: "token",
                conversationID: "conv",
                currentUserID: "me"
            ),
            title: "会話"
        )
    }
}
