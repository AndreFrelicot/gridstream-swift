import SwiftUI

struct VideoTagsDisplay: View {
    let tags: [TagInfo]
    var isCompact: Bool = false

    private var tagIds: String {
        tags.map { $0.id.uuidString }.joined(separator: ",")
    }

    var body: some View {
        Group {
            if !tags.isEmpty {
                VStack(alignment: .trailing, spacing: isCompact ? 4 : 6) {
                    ForEach(tags) { tag in
                        HStack(spacing: 4) {
                            Text(tag.name)
                                .font(isCompact ? .caption2 : .caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Circle()
                                .fill(tag.swiftUIColor)
                                .frame(width: isCompact ? 8 : 10, height: isCompact ? 8 : 10)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .id(tagIds)
    }
}
