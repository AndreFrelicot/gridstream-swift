import SwiftUI

struct AnnotationTextView: View {
    @Binding var text: String
    var onTextChanged: (String) -> Void
    var onDone: () -> Void

    @State private var localText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $localText)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .focused($isFocused)

                if localText.isEmpty {
                    Text("Add annotation text...")
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .padding(20)
            .background(Color.black.opacity(0.96).ignoresSafeArea())
            .navigationTitle("Annotation Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !localText.isEmpty {
                        Button("Clear") {
                            localText = ""
                            onTextChanged("")
                        }
                    }
                }
            }
        }
        // The sheet is black in both appearances: its text must stay light.
        .preferredColorScheme(.dark)
        .onAppear {
            localText = text
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: text) { _, newValue in
            if localText != newValue {
                localText = newValue
            }
        }
        .onChange(of: localText) { _, newValue in
            onTextChanged(newValue)
        }
    }
}

struct AnnotationTextOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 420)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
    }
}
