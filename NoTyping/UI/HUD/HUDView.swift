import SwiftUI

struct HUDView: View {
    @EnvironmentObject private var controller: HUDController

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.stateText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !controller.detailText.isEmpty {
                    Text(controller.detailText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            if isRecording {
                volumeBar
            }
            if controller.isDismissible {
                Spacer(minLength: 4)
                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minWidth: 200, maxWidth: 400, minHeight: 40, maxHeight: 40)
    }

    private var isRecording: Bool {
        controller.stateText.contains("Recording") || controller.stateText.contains("录音")
    }

    private var isProcessing: Bool {
        controller.stateText.contains("Transcribing") || controller.stateText.contains("Polishing")
            || controller.stateText.contains("转写") || controller.stateText.contains("润色")
    }

    private var isDone: Bool {
        controller.stateText.contains("Done") || controller.stateText.contains("完成")
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if controller.isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        } else if isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        } else if isProcessing {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else if isRecording {
            PulsingDot()
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }

    private var volumeBar: some View {
        GeometryReader { _ in
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.3))
                .frame(width: 60, height: 4)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: CGFloat(min(controller.volumeLevel, 1.0)) * 60, height: 4)
                        .animation(.linear(duration: 0.1), value: controller.volumeLevel)
                }
        }
        .frame(width: 60, height: 4)
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
