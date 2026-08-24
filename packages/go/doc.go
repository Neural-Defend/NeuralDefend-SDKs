// Package neuraldefend is the official Go client for the NeuroVerify image and
// video authenticity API.
//
// Use [NewClient] or [NewStagingClient] to construct a client, then call
// [Client.DetectImage] or [Client.DetectVideo] with a [Media] value built from
// [FileMedia], [BytesMedia], or [ReaderMedia].
package neuraldefend
