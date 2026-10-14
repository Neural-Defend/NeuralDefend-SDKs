# Module neuraldefend

Official Kotlin and Java SDK for the Neural Defend NeuroVerify image and video authenticity API.

Start with `com.neuraldefend.NeuroVerifyClient`. Branch on `ImageResult.status` and
`VideoResult.status`: rejections are results, not exceptions. Operational failures throw a
subclass of `com.neuraldefend.NeuroVerifyError`.

# Package com.neuraldefend

Client, media inputs, normalized results, and errors.
