import SwiftUI

/// Shows actual free space on the volume holding Cosmos data. This is a
/// headroom warning, not a claimed minimum size for every game.
struct CosmosStorageNotice: View {
    @State private var freeBytes: Int64? = Self.availableBytes()
    private let warningThreshold: Int64 = 10 * 1024 * 1024 * 1024

    var body: some View {
        Group {
            if let freeBytes, freeBytes < warningThreshold {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Low storage · \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free")
                            .font(.subheadline.weight(.semibold))
                        Text("Free up space before downloading or installing games. Allow room for the installer, the installed game, and its Windows environment.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Recheck", action: refresh).controlSize(.small)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        freeBytes = Self.availableBytes()
    }

    private static func availableBytes() -> Int64? {
        var path = CosmosPaths.supportDirectory
        while !FileManager.default.fileExists(atPath: path.path), path.path != "/" {
            path.deleteLastPathComponent()
        }
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }
}
