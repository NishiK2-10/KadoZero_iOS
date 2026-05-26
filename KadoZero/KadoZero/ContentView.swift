//
//  ContentView.swift
//  KadoZero
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Text("KadoZero")
                .font(.headline)
                .padding()

            Divider()

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
                    guard let lastId = viewModel.messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
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
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    @State private var glowPhase = 0.0
    @State private var burstTrigger = false
    @State private var displayText = ""
    @State private var textOpacity = 1.0

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            ZStack {
                if burstTrigger {
                    BubbleBurstView()
                        .frame(width: 120, height: 60)
                        .allowsHitTesting(false)
                }

                Text(displayText)
                    .opacity(textOpacity)
                    .padding(12)
                    .background(bubbleBackground)
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                glowStrokeStyle,
                                lineWidth: 2
                            )
                            .rotationEffect(.degrees(glowPhase))
                    )
                    .shadow(
                        color: message.isConverting ? .cyan.opacity(0.6) : .clear,
                        radius: message.isConverting ? 12 : 0
                    )
            }

            if !message.isUser { Spacer() }
        }
        .onAppear {
            displayText = message.text
            if message.isConverting {
                startGlow()
            }
        }
        .onChange(of: message.isConverting) { _, newValue in
            if newValue {
                startGlow()
            } else {
                glowPhase = 0
                playTextSwapEffect(newText: message.text)
            }
        }
        .onChange(of: message.text) { _, newValue in
            guard newValue != displayText else { return }
            if message.isConverting {
                displayText = newValue
            } else {
                playTextSwapEffect(newText: newValue)
            }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isUser {
            if message.isConverting {
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [.pink, .purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            return AnyShapeStyle(Color.blue)
        }
        return AnyShapeStyle(Color.gray.opacity(0.3))
    }

    private var glowStrokeStyle: AnyShapeStyle {
        if message.isConverting {
            return AnyShapeStyle(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                    center: .center
                )
            )
        }
        return AnyShapeStyle(Color.clear)
    }

    private func startGlow() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            glowPhase = 360
        }
    }

    private func playTextSwapEffect(newText: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            textOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            displayText = newText
            burstTrigger = true
            withAnimation(.easeIn(duration: 0.22)) {
                textOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                burstTrigger = false
            }
        }
    }
}

struct BubbleBurstView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 8, height: 8)
                    .offset(bubbleOffset(index: index))
                    .scaleEffect(animate ? 1 : 0.2)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 0.45).delay(Double(index) * 0.02), value: animate)
            }
        }
        .onAppear {
            animate = true
        }
    }

    private func bubbleOffset(index: Int) -> CGSize {
        let angle = Double(index) * (Double.pi * 2 / 8)
        let radius: CGFloat = animate ? 34 : 4
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius * 0.6)
    }
}

#Preview {
    ContentView()
}
