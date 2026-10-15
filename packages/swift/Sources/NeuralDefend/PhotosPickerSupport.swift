#if canImport(PhotosUI) && canImport(SwiftUI) && canImport(CoreTransferable) && !os(tvOS) && !os(watchOS)
    import CoreTransferable
    import Foundation
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
    extension MediaInput {
        /// Loads a photo or video chosen with SwiftUI's `PhotosPicker`.
        ///
        /// The system copies the item into a private temporary file, which streams from disk like
        /// ``file(_:filename:)`` and is deleted when the last copy of this input is released. The
        /// filename, and therefore the content type, comes from the Photos library.
        ///
        /// - Throws: ``NeuroVerifyError/validation(code:message:)`` with
        ///   ``ValidationErrorCode/unsupportedInput`` when the item cannot be loaded.
        public init(photosPickerItem item: PhotosPickerItem) async throws {
            let picked: PickedMediaFile?
            do {
                picked = try await item.loadTransferable(type: PickedMediaFile.self)
            } catch {
                throw NeuroVerifyError.validation(
                    code: .unsupportedInput,
                    message: "The selected item could not be loaded: \(error.localizedDescription)"
                )
            }
            guard let picked else {
                throw NeuroVerifyError.validation(
                    code: .unsupportedInput,
                    message: "The selected item has no image or video data."
                )
            }
            self.init(
                source: .file(picked.url),
                filename: picked.url.lastPathComponent,
                temporaryFile: TemporaryFile(url: picked.directory)
            )
        }
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, visionOS 1.0, *)
    struct PickedMediaFile: Transferable, Sendable {
        let url: URL
        let directory: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .movie) { received in
                try copy(received)
            }
            FileRepresentation(importedContentType: .image) { received in
                try copy(received)
            }
        }

        /// The received file is only valid inside the import closure, so it is copied.
        private static func copy(_ received: ReceivedTransferredFile) throws -> PickedMediaFile {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("neuraldefend-picked-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMediaFile(url: destination, directory: directory)
        }
    }
#endif
