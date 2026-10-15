# Module neuraldefend-kotlin

Official Kotlin SDK for the Neural Defend NeuroVerify image and video authenticity API.

Start with `com.neuraldefend.kotlin.NeuroVerifyClient`. Branch on `ImageResult.status` and
`VideoResult.status`: rejections are results, not exceptions. Operational failures throw a
subclass of `com.neuraldefend.kotlin.NeuroVerifyError`.

# Package com.neuraldefend.kotlin

Client, media inputs, normalized results, and errors.
