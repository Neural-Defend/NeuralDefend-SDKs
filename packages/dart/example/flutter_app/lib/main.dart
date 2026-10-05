import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:neuraldefend/neuraldefend.dart';

// Demo configuration, supplied with --dart-define. A key compiled into an app
// can be extracted by anyone who installs it: use a staging key here and call
// NeuroVerify from your backend in production.
const String _apiKey = String.fromEnvironment('NEURALDEFEND_API_KEY');
const bool _production = bool.fromEnvironment('NEURALDEFEND_PRODUCTION');

void main() {
  runApp(const NeuroVerifyExampleApp());
}

enum MediaKind { image, video }

typedef MediaPicker = Future<XFile?> Function(MediaKind kind);

Future<XFile?> pickFromGallery(MediaKind kind) {
  final picker = ImagePicker();
  return switch (kind) {
    MediaKind.image => picker.pickImage(source: ImageSource.gallery),
    MediaKind.video => picker.pickVideo(source: ImageSource.gallery),
  };
}

NeuroVerifyClient createDemoClient() => _production
    ? NeuroVerifyClient(apiKey: _apiKey)
    : NeuroVerifyClient.staging(apiKey: _apiKey);

class NeuroVerifyExampleApp extends StatelessWidget {
  const NeuroVerifyExampleApp({
    super.key,
    this.clientFactory = createDemoClient,
    this.picker = pickFromGallery,
    this.production = _production,
  });

  final NeuroVerifyClient Function() clientFactory;
  final MediaPicker picker;
  final bool production;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroVerify example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: DetectionPage(
        clientFactory: clientFactory,
        picker: picker,
        production: production,
      ),
    );
  }
}

class DetectionPage extends StatefulWidget {
  const DetectionPage({
    super.key,
    required this.clientFactory,
    required this.picker,
    required this.production,
  });

  final NeuroVerifyClient Function() clientFactory;
  final MediaPicker picker;
  final bool production;

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  NeuroVerifyClient? _client;
  String? _configurationError;
  Completer<void>? _abort;
  bool _busy = false;
  double? _progress;
  Outcome? _outcome;

  @override
  void initState() {
    super.initState();
    try {
      _client = widget.clientFactory();
    } on ValidationError catch (error) {
      _configurationError = error.code == ValidationErrorCode.apiKeyRequired
          ? 'No API key configured. Run with '
              '--dart-define=NEURALDEFEND_API_KEY=<staging key>.'
          : error.detail;
    }
  }

  @override
  void dispose() {
    _cancel();
    _client?.close();
    super.dispose();
  }

  void _cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void _onProgress(int sent, int total) {
    if (!mounted || total == 0) return;
    setState(() => _progress = sent / total);
  }

  Future<void> _analyze(MediaKind kind) async {
    final client = _client;
    if (client == null || _busy) return;
    final file = await widget.picker(kind);
    if (file == null || !mounted) return;

    final abort = Completer<void>();
    setState(() {
      _busy = true;
      _progress = 0;
      _outcome = null;
      _abort = abort;
    });
    try {
      final media = MediaInput.openRead(
        file.openRead,
        length: await file.length(),
        filename: file.name,
      );
      final outcome = switch (kind) {
        MediaKind.image => Outcome.fromImage(await client.detectImage(
            media,
            abortTrigger: abort.future,
            onProgress: _onProgress,
          )),
        MediaKind.video => Outcome.fromVideo(await client.detectVideo(
            media,
            abortTrigger: abort.future,
            onProgress: _onProgress,
          )),
      };
      _show(outcome);
    } on AbortError {
      _show(const Outcome(
          'Cancelled', ['The upload was cancelled.'], Tone.neutral));
    } on NeuroVerifyError catch (error) {
      _show(Outcome.fromError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _abort = null;
        });
      }
    }
  }

  void _show(Outcome outcome) {
    if (mounted) setState(() => _outcome = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configurationError = _configurationError;
    final outcome = _outcome;
    return Scaffold(
      appBar: AppBar(title: const Text('NeuroVerify example')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.production ? 'Production API' : 'Staging API',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Demo build: the API key is compiled into this app. In production, '
            'upload to your backend and call NeuroVerify from there.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (configurationError != null)
            OutcomeCard(Outcome(
                'Configuration needed', [configurationError], Tone.error))
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _analyze(MediaKind.image),
              icon: const Icon(Icons.face),
              label: const Text('Check a photo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _analyze(MediaKind.video),
              icon: const Icon(Icons.videocam),
              label: const Text('Check a video'),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress == 1 ? null : _progress),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(_progress == 1
                      ? 'Analyzing…'
                      : 'Uploading ${((_progress ?? 0) * 100).round()}%'),
                ),
                TextButton(onPressed: _cancel, child: const Text('Cancel')),
              ],
            ),
          ],
          if (outcome != null) ...[
            const SizedBox(height: 24),
            OutcomeCard(outcome),
            if (outcome.scored) ...[
              const SizedBox(height: 8),
              Text(
                'Risk levels are decision support, not proof. Review high-risk '
                'results before taking action.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum Tone { low, medium, high, neutral, error }

/// What the example shows for a result or failure.
class Outcome {
  const Outcome(this.title, this.lines, this.tone);

  factory Outcome.fromImage(ImageResult result) => switch (result.status) {
        ResultStatus.success => Outcome(
            '${_label(result.riskLevel)} risk',
            [
              result.message,
              'Score ${result.riskScore} of 10',
              'Transaction ${result.uniqueTrxId}',
            ],
            _tone(result.riskLevel),
          ),
        ResultStatus.rejected => Outcome(
            'Not scored',
            [
              result.message,
              'Billable: ${result.billable ? 'yes' : 'no'}',
              'Transaction ${result.uniqueTrxId}',
            ],
            Tone.neutral,
          ),
        ResultStatus.unknown =>
          _unknown(result.originalStatus, result.uniqueTrxId),
      };

  factory Outcome.fromVideo(VideoResult result) {
    switch (result.status) {
      case ResultStatus.success:
        final highest = [result.videoRiskLevel, result.audioRiskLevel]
            .whereType<RiskLevel>()
            .fold<RiskLevel?>(
                null, (a, b) => a == null || b.index > a.index ? b : a);
        return Outcome(
          '${_label(highest)} risk',
          [
            'Video: ${_label(result.videoRiskLevel)} (${result.videoRiskScore})',
            result.hasAudio
                ? 'Audio: ${_label(result.audioRiskLevel)} (${result.audioRiskScore})'
                : 'Audio: ${result.audioMessage ?? 'not scored'}',
            'Transaction ${result.uniqueTrxId}',
          ],
          _tone(highest),
        );
      case ResultStatus.rejected:
        return Outcome(
          'Not scored',
          [
            result.videoMessage,
            'Billable: ${result.billable ? 'yes' : 'no'}',
            'Transaction ${result.uniqueTrxId}',
          ],
          Tone.neutral,
        );
      case ResultStatus.unknown:
        return _unknown(result.originalStatus, result.uniqueTrxId);
    }
  }

  factory Outcome.fromError(NeuroVerifyError error) {
    final (title, hint) = switch (error) {
      ValidationError() => ('Check the file', error.detail),
      AuthenticationError() => (
          'API key rejected',
          'Check the key and environment.'
        ),
      ScopeError() => ('Not enabled', 'This key cannot use this endpoint.'),
      RateLimitError(:final retryAfter) => (
          'Too many requests',
          retryAfter == null
              ? 'Try again later.'
              : 'Try again in ${retryAfter.inSeconds}s.',
        ),
      TimeoutError() || NetworkError() => (
          'Could not reach NeuroVerify',
          'Check your connection. The request may still have been processed.',
        ),
      _ => ('Service error', error.detail),
    };
    return Outcome(
        title,
        [hint, if (error.requestId != null) 'Request ${error.requestId}'],
        Tone.error);
  }

  final String title;
  final List<String> lines;
  final Tone tone;

  bool get scored =>
      tone == Tone.low || tone == Tone.medium || tone == Tone.high;

  static Outcome _unknown(String status, String trxId) => Outcome(
        'Unrecognized result',
        [
          'The API returned "$status". Update the neuraldefend package.',
          'Transaction $trxId'
        ],
        Tone.neutral,
      );

  static String _label(RiskLevel? level) => switch (level) {
        RiskLevel.low => 'Low',
        RiskLevel.medium => 'Medium',
        RiskLevel.high => 'High',
        null => 'Unknown',
      };

  static Tone _tone(RiskLevel? level) => switch (level) {
        RiskLevel.low => Tone.low,
        RiskLevel.medium => Tone.medium,
        RiskLevel.high => Tone.high,
        null => Tone.neutral,
      };
}

class OutcomeCard extends StatelessWidget {
  const OutcomeCard(this.outcome, {super.key});

  final Outcome outcome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (outcome.tone) {
      Tone.low => (Colors.green.shade700, Icons.verified_user),
      Tone.medium => (Colors.orange.shade800, Icons.help),
      Tone.high => (scheme.error, Icons.gpp_maybe),
      Tone.error => (scheme.error, Icons.error_outline),
      Tone.neutral => (scheme.onSurfaceVariant, Icons.info_outline),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  outcome.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in outcome.lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }
}
