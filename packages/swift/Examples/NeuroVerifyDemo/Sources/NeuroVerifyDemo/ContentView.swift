#if canImport(SwiftUI) && canImport(PhotosUI)
    import NeuralDefend
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    /// Pick a photo or video, upload it, and show the outcome.
    ///
    /// Add this package to an iOS app target, then show
    /// `ContentView(model: DetectionModel(client: client))` from your `App`.
    public struct ContentView: View {
        @State private var model: DetectionModel
        @State private var selection: PhotosPickerItem?
        @State private var loadError: String?

        public init(model: DetectionModel) {
            _model = State(initialValue: model)
        }

        public var body: some View {
            VStack(spacing: 24) {
                Text("NeuroVerify demo").font(.title2.bold())

                PhotosPicker(selection: $selection, matching: .any(of: [.images, .videos])) {
                    Label("Choose a photo or video", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading)

                status

                if isUploading {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
            }
            .padding()
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }

        private var isUploading: Bool {
            if case .uploading = model.phase { return true }
            return false
        }

        @ViewBuilder
        private var status: some View {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                switch model.phase {
                case .idle:
                    Text("Results are decision-support signals, not proof.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .uploading(let fraction):
                    ProgressView(value: fraction) { Text("Uploading") }
                case .finished(let summary):
                    VStack(spacing: 8) {
                        Text(summary.title).font(.headline)
                        Text(summary.detail).multilineTextAlignment(.center)
                        Text(summary.transactionID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
        }

        private func load(_ item: PhotosPickerItem) async {
            loadError = nil
            do {
                let media = try await MediaInput(photosPickerItem: item)
                let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                model.start(media, isVideo: isVideo)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
#endif
