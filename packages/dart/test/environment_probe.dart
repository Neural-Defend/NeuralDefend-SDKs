import 'package:neuraldefend/neuraldefend.dart';

/// Run by `client_test.dart` in a child process with a controlled environment.
void main() {
  final client = NeuroVerifyClient();
  final staging = NeuroVerifyClient.staging();
  // ignore: avoid_print
  print('${client.baseUrl}|staging-pinned=${staging.baseUrl}');
  client.close();
  staging.close();
}
