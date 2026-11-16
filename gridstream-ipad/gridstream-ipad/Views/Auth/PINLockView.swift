import SwiftUI

struct PINLockView: View {
    let serverName: String?
    let errorMessage: String?
    /// When set and in the future, the server is rate-limiting PIN attempts:
    /// the Unlock button stays disabled and a countdown is shown.
    var retryAfter: Date? = nil
    let onSubmit: (String) async -> Void

    @State private var pin = ""
    @State private var submitting = false

    var body: some View {
        ZStack {
            OnboardingBackground()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = remainingLockout(at: context.date)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GridStream")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)

                        Text("Unlock this iPad")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(serverName ?? String(localized: "Enter the server PIN to continue."))
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .padding()
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)

                    if let remaining {
                        Text("Too many attempts. Try again in \(ServerSessionManager.formatDelay(remaining)).")
                            .font(.footnote)
                            .foregroundStyle(Color.onboardingAlert)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.onboardingAlert)
                    }

                    Button {
                        Task {
                            guard !pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            submitting = true
                            await onSubmit(pin)
                            submitting = false
                            pin = ""
                        }
                    } label: {
                        Text(submitting ? "Unlocking..." : "Unlock")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundStyle(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(submitting || pin.isEmpty || remaining != nil)
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .padding()
        }
    }

    private func remainingLockout(at date: Date) -> TimeInterval? {
        guard let retryAfter else { return nil }
        let remaining = retryAfter.timeIntervalSince(date)
        return remaining > 0 ? remaining : nil
    }
}
