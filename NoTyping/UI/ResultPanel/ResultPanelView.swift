import SwiftUI

struct ResultPanelView: View {
    @EnvironmentObject private var controller: ResultPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close and copy buttons
            HStack {
                Text("Transcription")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    controller.copyToClipboard()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: controller.isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(controller.isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(controller.isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Text content
            ScrollView {
                Text(controller.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            .frame(maxHeight: 300)

            // Footer with timestamp
            HStack {
                Text(controller.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .frame(maxHeight: 400)
    }
}
