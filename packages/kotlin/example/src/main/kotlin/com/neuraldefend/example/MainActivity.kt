package com.neuraldefend.example

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.neuraldefend.kotlin.MediaInput
import com.neuraldefend.android.MediaInputs
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as ExampleApplication
        val factory = viewModelFactory { initializer { DetectViewModel({ app.clientFactory }) } }
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    DetectRoute(viewModel(factory = factory))
                }
            }
        }
    }
}

@Composable
private fun DetectRoute(viewModel: DetectViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current.applicationContext
    val pickImage = rememberLauncherForActivityResult(PickVisualMedia()) { uri: Uri? ->
        if (uri != null) viewModel.analyze(MediaKind.IMAGE, "Photo") { MediaInputs.fromUri(context, uri) }
    }
    val pickVideo = rememberLauncherForActivityResult(PickVisualMedia()) { uri: Uri? ->
        if (uri != null) viewModel.analyze(MediaKind.VIDEO, "Video") { MediaInputs.fromUri(context, uri) }
    }
    DetectScreen(
        state = state,
        onApiKeyChange = viewModel::onApiKeyChange,
        onEnvironmentChange = viewModel::onEnvironmentChange,
        onPickImage = { pickImage.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) },
        onPickVideo = { pickVideo.launch(PickVisualMediaRequest(PickVisualMedia.VideoOnly)) },
        onSampleImage = {
            viewModel.analyze(MediaKind.IMAGE, "Sample image") { sample(context, SAMPLE_IMAGE) }
        },
        onSampleVideo = {
            viewModel.analyze(MediaKind.VIDEO, "Sample video") { sample(context, SAMPLE_VIDEO) }
        },
        onCancel = viewModel::cancel,
    )
}

internal const val SAMPLE_IMAGE = "ai-generated.png"
internal const val SAMPLE_VIDEO = "fake-video.mp4"

/** Copies a bundled sample out of the APK once so it can be uploaded as a plain file. */
private fun sample(context: Context, name: String): MediaInput {
    val file = File(context.cacheDir, name)
    if (!file.isFile) {
        val partial = File(context.cacheDir, "$name.partial")
        context.assets.open(name).use { input -> partial.outputStream().use { input.copyTo(it) } }
        partial.renameTo(file)
    }
    return MediaInput.file(file)
}

@Composable
fun DetectScreen(
    state: DetectUiState,
    onApiKeyChange: (String) -> Unit,
    onEnvironmentChange: (Environment) -> Unit,
    onPickImage: () -> Unit,
    onPickVideo: () -> Unit,
    onSampleImage: () -> Unit,
    onSampleVideo: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("NeuroVerify", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Demo only: the key stays in memory on this device. Production apps should send media " +
                "through their own backend so the API key never ships in an APK.",
            style = MaterialTheme.typography.bodySmall,
        )
        OutlinedTextField(
            value = state.apiKey,
            onValueChange = onApiKeyChange,
            label = { Text("API key") },
            singleLine = true,
            enabled = !state.busy,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth().testTag("apiKey"),
        )
        Column(Modifier.selectableGroup()) {
            Environment.entries.forEach { environment ->
                val selected = state.environment == environment
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .selectable(selected, enabled = !state.busy, role = Role.RadioButton) {
                            onEnvironmentChange(environment)
                        }
                        .testTag("environment-${environment.name.lowercase()}"),
                ) {
                    RadioButton(selected = selected, onClick = null, enabled = !state.busy)
                    Text(
                        if (environment == Environment.STAGING) "Staging" else "Production",
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(onClick = onPickImage, enabled = !state.busy, modifier = Modifier.weight(1f)) { Text("Pick photo") }
            Button(onClick = onPickVideo, enabled = !state.busy, modifier = Modifier.weight(1f)) { Text("Pick video") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(
                onClick = onSampleImage,
                enabled = !state.busy,
                modifier = Modifier.weight(1f).testTag("sampleImage"),
            ) { Text("Sample image") }
            OutlinedButton(
                onClick = onSampleVideo,
                enabled = !state.busy,
                modifier = Modifier.weight(1f).testTag("sampleVideo"),
            ) { Text("Sample video") }
        }
        PhaseView(state.phase, onCancel)
    }
}

@Composable
private fun PhaseView(phase: Phase, onCancel: () -> Unit) {
    when (phase) {
        Phase.Idle -> Unit
        is Phase.Uploading -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val fraction = if (phase.totalBytes > 0) phase.sentBytes.toFloat() / phase.totalBytes else 0f
            Text(
                if (phase.totalBytes > 0 && phase.sentBytes >= phase.totalBytes) {
                    "${phase.label}: waiting for the analysis…"
                } else {
                    "${phase.label}: uploading ${(fraction * 100).toInt()}%"
                },
            )
            LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth().testTag("progress"))
            OutlinedButton(onClick = onCancel, modifier = Modifier.testTag("cancel")) { Text("Cancel") }
        }
        is Phase.Done -> Card(Modifier.fillMaxWidth().testTag("result")) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(phase.summary.headline, style = MaterialTheme.typography.titleMedium)
                phase.summary.details.forEach { Text(it, style = MaterialTheme.typography.bodyMedium) }
            }
        }
        is Phase.Failed -> Card(
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
            modifier = Modifier.fillMaxWidth().testTag("error"),
        ) {
            Text(phase.message, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onErrorContainer)
        }
        Phase.Cancelled -> Text("Upload cancelled.", modifier = Modifier.testTag("cancelled"))
    }
}

@Preview(showBackground = true)
@Composable
private fun DetectScreenPreview() {
    MaterialTheme {
        DetectScreen(
            state = DetectUiState(
                apiKey = "key",
                phase = Phase.Done(ResultSummary("Image: low risk (2.2 / 10)", listOf("Not likely to be Spoof or AI-generated"))),
            ),
            onApiKeyChange = {},
            onEnvironmentChange = {},
            onPickImage = {},
            onPickVideo = {},
            onSampleImage = {},
            onSampleVideo = {},
            onCancel = {},
        )
    }
}
