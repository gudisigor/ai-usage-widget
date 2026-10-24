import SwiftUI

enum ServiceID: String, CaseIterable, Identifiable {
    case chatgpt, claude, gemini, copilot, perplexity, cursor, grok, deepseek, mistral, msCopilot
    var id: String { rawValue }
}

struct ServiceInfo: Identifiable {
    let id: ServiceID
    let name: String
    let logo: String?            // SVG in Resources, nil → monogram
    let tint: Color
    let provider: UsageProvider? // nil → no usage source wired up yet
    let signInHint: String

    var isLive: Bool { provider != nil }
}

enum Registry {
    static let all: [ServiceInfo] = [
        .init(id: .chatgpt, name: "ChatGPT", logo: "openai", tint: .white,
              provider: ChatGPTProvider(), signInHint: "hintCodex"),
        .init(id: .claude, name: "Claude", logo: "claude", tint: Color(red: 0.85, green: 0.47, blue: 0.34),
              provider: ClaudeProvider(), signInHint: "hintClaude"),
        .init(id: .gemini, name: "Gemini", logo: "googlegemini", tint: Color(red: 0.48, green: 0.65, blue: 0.97), provider: nil, signInHint: ""),
        .init(id: .copilot, name: "GitHub Copilot", logo: "githubcopilot", tint: .white, provider: nil, signInHint: ""),
        .init(id: .perplexity, name: "Perplexity", logo: "perplexity", tint: Color(red: 0.13, green: 0.72, blue: 0.80), provider: nil, signInHint: ""),
        .init(id: .cursor, name: "Cursor", logo: nil, tint: .gray, provider: nil, signInHint: ""),
        .init(id: .grok, name: "Grok", logo: nil, tint: .gray, provider: nil, signInHint: ""),
        .init(id: .deepseek, name: "DeepSeek", logo: nil, tint: Color(red: 0.30, green: 0.42, blue: 1.0), provider: nil, signInHint: ""),
        .init(id: .mistral, name: "Mistral", logo: nil, tint: Color(red: 0.98, green: 0.32, blue: 0.06), provider: nil, signInHint: ""),
        .init(id: .msCopilot, name: "Microsoft Copilot", logo: nil, tint: Color(red: 0.2, green: 0.6, blue: 0.95), provider: nil, signInHint: ""),
    ]

    static func info(_ id: ServiceID) -> ServiceInfo { all.first { $0.id == id }! }
}

/// Brand logo from Resources, or a monogram when there is no SVG.
struct ServiceLogo: View {
    let info: ServiceInfo

    var body: some View {
        if let name = info.logo,
           let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().scaledToFit()
        } else {
            ZStack {
                Circle().fill(info.tint.opacity(0.25))
                Text(String(info.name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundColor(info.tint)
            }
        }
    }
}
