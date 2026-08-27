import SwiftUI

/// One decoded code, with the obvious follow-up actions.
/// Opening a link is always an explicit tap — Cod never navigates on its own.
struct BarcodePayloadRow: View {
    let payload: String
    var symbology: String?

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var url: URL? {
        guard let url = URL(string: payload), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let symbology {
                Text(symbology.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text(payload)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(6)

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = payload
                    withAnimation { copied = true }
                    Haptics.success()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let url {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open", systemImage: "safari")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}
