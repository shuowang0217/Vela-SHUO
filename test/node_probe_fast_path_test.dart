import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/network/flclash_core_api.dart';

class _TimingTransport implements FlClashCoreTransport {
  Map<String, dynamic>? request;
  @override
  Future<String?> invoke(String json) async {
    final call = jsonDecode(json) as Map<String, dynamic>;
    request = call;
    return jsonEncode({'id': call['id'], 'result': {
      'status-code': 204, 'delay': 120,
    }});
  }
}

void main() {
  test('single-node probe uses custom native deadline, not Dart timing',
      () async {
    final transport = _TimingTransport();
    final api = FlClashCoreApi(transport);
    final sample = await api.probe('https://cp.cloudflare.com/generate_204',
        'JP-01', timeoutMs: 4000) as Map;
    expect(sample['delay'], 120);
    expect(transport.request?['arguments']['timeout'], 4000);
    expect(transport.request?['arguments']['proxy-name'], 'JP-01');
  });

  test('native speed controls remain bounded and preserve full 1 MiB bytes',
      () {
    final source = File(
        'scripts/migration/flclash_native/vela_profile_windows.go')
        .readAsStringSync();
    expect(source, contains('const concurrency = 20'));
    expect(source, contains('timeout := int64(2400)'));
    expect(source, contains('timeout = 1600'));
    expect(source, contains('Timeout: timeoutMs'));
    expect(source, contains('524288'));
    expect(source, contains('512 * 1024'));
    expect(source, contains('11000'));
    expect(source, contains('reasonPriority'));
    expect(source, contains('received, elapsedUs, reason'));
    expect(source, contains('velaDownloadLimit int64 = 1024 * 1024'));
    expect(source, contains('MaxBody: byteLimit'));
    expect(source, contains('velaDownloadLimit int64 = 1024 * 1024'));
    expect(source, contains('maxBytes int64'));
    expect(source, contains('received, elapsedUs, reason'));
    expect(source, contains('mbps := float64(received)'));
    expect(source, contains('velaLocalDownloadURL(params.TestURL)'));
    // Regression: beta.2 parallel downloads returned no samples on devices.
    // Keep native download requests sequential while latency workers remain 20.
    expect(source, contains('for _, endpoint := range endpoints {'));
    expect(source, contains('received, elapsedUs, reason := velaCustomDownload('));
    expect(source, contains('"https://speed.cloudflare.com/__down?bytes=1048576"'));
    expect(source, contains('"https://speed.cloudflare.com/__down?bytes=524288"'));
    expect(source, contains('"https://cachefly.cachefly.net/1mb.test"'));
    expect(source, contains('"https://proof.ovh.net/files/1Mb.dat"'));
    expect(source, contains('"ok": false, "reason": lastReason'));
    expect(source, isNot(contains('go velaCustomDownload(')));
  });
}
