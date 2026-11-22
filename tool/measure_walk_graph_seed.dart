import 'dart:io';

Future<void> main(List<String> arguments) async {
  final testPath = 'tool/walk_graph_worker_measurement_test.dart';
  final result = Platform.isWindows
      ? await Process.run(Platform.environment['COMSPEC'] ?? 'cmd.exe', [
          '/c',
          'flutter',
          'test',
          testPath,
        ], runInShell: true)
      : await Process.run('flutter', ['test', testPath]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exitCode = result.exitCode;
}
