import CarMediaKit
import SwiftUI
import UIKit

/// Channel logo loaded through ``ImageLoader`` with a symbol placeholder.
struct LogoView: View {
    let url: URL?
    var isRadio = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: isRadio ? "radio" : "tv")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = ImageLoader.shared.cachedImage(for: url)
            if image == nil {
                image = await ImageLoader.shared.image(for: url)
            }
        }
    }
}

/// One channel in a list: logo, title, "now / next" and progress.
struct ChannelRow: View {
    let title: String
    let logoURL: URL?
    let isRadio: Bool
    let summary: EPGSummary?
    let isFavorite: Bool
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            LogoView(url: logoURL, isRadio: isRadio)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                if let summary {
                    if let now = summary.nowLine {
                        Text(verbatim: now)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: summary.progress)
                            .progressViewStyle(.linear)
                    }
                    if let next = summary.nextLine {
                        Text("Sonra: \(next)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favori"))
            }
        }
        .padding(.vertical, 2)
    }
}
