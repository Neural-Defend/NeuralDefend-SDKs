package com.neuraldefend.example

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.neuraldefend.kotlin.AuthenticationError
import com.neuraldefend.kotlin.DetectionResult
import com.neuraldefend.kotlin.HttpError
import com.neuraldefend.kotlin.ImageResult
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.kotlin.NetworkError
import com.neuraldefend.kotlin.NeuroVerifyError
import com.neuraldefend.kotlin.ProtocolError
import com.neuraldefend.kotlin.RateLimitError
import com.neuraldefend.kotlin.ResultStatus
import com.neuraldefend.kotlin.RiskLevel
import com.neuraldefend.kotlin.ScopeError
import com.neuraldefend.kotlin.ServerError
import com.neuraldefend.kotlin.TimeoutError
import com.neuraldefend.kotlin.ValidationError
import com.neuraldefend.kotlin.ValidationErrorCode
import com.neuraldefend.kotlin.VideoResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.Locale

enum class MediaKind { IMAGE, VIDEO }

/** A finished result, already phrased for display. */
data class ResultSummary(val headline: String, val details: List<String>)

sealed interface Phase {
    data object Idle : Phase

    data class Uploading(val label: String, val sentBytes: Long, val totalBytes: Long) : Phase

    data class Done(val summary: ResultSummary) : Phase

    data class Failed(val message: String) : Phase

    data object Cancelled : Phase
}

data class DetectUiState(
    val apiKey: String = "",
    val environment: Environment = Environment.STAGING,
    val phase: Phase = Phase.Idle,
) {
    val busy: Boolean get() = phase is Phase.Uploading
}

class DetectViewModel(
    private val clientFactory: () -> ClientFactory,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    private val mutableState = MutableStateFlow(DetectUiState())
    val state: StateFlow<DetectUiState> = mutableState.asStateFlow()

    private var job: Job? = null

    fun onApiKeyChange(apiKey: String) = mutableState.update { it.copy(apiKey = apiKey) }

    fun onEnvironmentChange(environment: Environment) = mutableState.update { it.copy(environment = environment) }

    /**
     * Uploads the media returned by [open], which runs off the main thread because content
     * providers may do disk or network I/O.
     */
    fun analyze(kind: MediaKind, label: String, open: () -> MediaInput) {
        if (state.value.busy) return
        val snapshot = state.value
        mutableState.update { it.copy(phase = Phase.Uploading(label, 0, 0)) }
        job = viewModelScope.launch {
            val phase = try {
                val summary = withContext(ioDispatcher) {
                    clientFactory().create(snapshot.apiKey.trim(), snapshot.environment).use { client ->
                        val media = open()
                        val progress = { sent: Long, total: Long ->
                            mutableState.update { current ->
                                if (current.phase is Phase.Uploading) current.copy(phase = Phase.Uploading(label, sent, total)) else current
                            }
                        }
                        when (kind) {
                            MediaKind.IMAGE -> summarize(client.detectImage(media, progress))
                            MediaKind.VIDEO -> summarize(client.detectVideo(media, onProgress = progress))
                        }
                    }
                }
                Phase.Done(summary)
            } catch (cancelled: CancellationException) {
                mutableState.update { it.copy(phase = Phase.Cancelled) }
                throw cancelled
            } catch (error: NeuroVerifyError) {
                Phase.Failed(describe(error))
            } catch (_: IOException) {
                Phase.Failed("Couldn't read the selected file.")
            }
            mutableState.update { it.copy(phase = phase) }
        }
    }

    fun cancel() {
        job?.cancel()
    }
}

internal fun summarize(result: DetectionResult): ResultSummary = when (result.status) {
    ResultStatus.REJECTED -> ResultSummary(
        "Not analyzed",
        listOfNotNull(rejectionMessage(result), "NeuroVerify rejected this file, so there is no score."),
    )
    ResultStatus.UNKNOWN -> ResultSummary(
        "Unrecognized status",
        listOf("The service returned status \"${result.originalStatus}\". Update the SDK to interpret it."),
    )
    ResultStatus.SUCCESS -> when (result) {
        is ImageResult -> ResultSummary(
            "Image: ${riskText(result.riskLevel, result.originalRiskLevel, result.riskScore)}",
            listOfNotNull(result.message, "Transaction ${result.uniqueTrxId}"),
        )
        is VideoResult -> ResultSummary(
            "Video: ${riskText(result.videoRiskLevel, result.originalVideoRiskLevel, result.videoRiskScore)}",
            listOfNotNull(
                result.videoMessage,
                if (result.hasAudio) {
                    "Audio: ${riskText(result.audioRiskLevel, result.originalAudioRiskLevel, result.audioRiskScore)}"
                } else {
                    "Audio: no audio track was scored"
                },
                result.audioMessage,
                "Transaction ${result.uniqueTrxId}",
            ),
        )
    }
}

private fun rejectionMessage(result: DetectionResult): String? = when (result) {
    is ImageResult -> result.message
    is VideoResult -> result.videoMessage
}

private fun riskText(level: RiskLevel?, original: String?, score: Double?): String {
    val name = when (level) {
        RiskLevel.LOW -> "low risk"
        RiskLevel.MEDIUM -> "medium risk"
        RiskLevel.HIGH -> "high risk"
        null -> original?.let { "risk \"$it\"" } ?: "no risk level"
    }
    return if (score == null) name else "$name (${String.format(Locale.US, "%.1f", score)} / 10)"
}

internal fun describe(error: NeuroVerifyError): String = when (error) {
    is ValidationError -> when (error.code) {
        ValidationErrorCode.API_KEY_REQUIRED -> "Enter an API key first."
        else -> "This file can't be sent: ${error.detail}"
    }
    is AuthenticationError -> "The API key was rejected (401): ${error.detail}"
    is ScopeError -> "This API key isn't allowed to use this endpoint (403)."
    is RateLimitError -> {
        val seconds = error.retryAfterMillis?.let { (it + 999) / 1000 }
        if (seconds == null) "Too many requests. Try again later." else "Too many requests. Try again in $seconds s."
    }
    is ServerError -> "NeuroVerify had a problem (${error.statusCode}). Try again later."
    is HttpError -> "The request failed (${error.statusCode}): ${error.detail}"
    is TimeoutError -> "The upload took too long. Check your connection and try again."
    is NetworkError -> "Couldn't reach NeuroVerify. Check your connection."
    is ProtocolError -> "NeuroVerify sent a response this app doesn't understand."
    else -> error.detail
}
