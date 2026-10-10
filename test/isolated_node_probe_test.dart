import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/smart/vela_node_probe.dart';
import 'package:vela_shuo/src/smart/vela_download_probe.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';

class _Handle implements VelaCoreHandle {
  final _done = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => _done.future;
  @override
  void kill() {
    killed = true;
    if (!_done.isCompleted) { _done.complete(0); }
  }
}

class _Runner implements VelaCoreRunner {
  String? configText;
  bool checkFails = false;
  _Handle? process;

  @override
  Future<void> check(String binary, String config) async {
    configText = await File(config).readAsString();
    if (checkFails) {
      throw const FormatException('Secret should not enter error logs');
    }
  }

  @override
  Future<void> assertPortFree(int port) async {}
  @override
  Future<VelaCoreHandle> launch(String binary, String config) async {
    process = _Handle();
    return process!;
  }
  @override
  Future<bool> awaitLocalListener(int port) async => true;
}

class _Https implements VelaRemoteProbe {
  int? lastPort;
  @override
  Future<bool> verify(int port) async {
    lastPort = port;
    return true;
  }
}

class _Download implements VelaDownloadTransport {
  bool succeed = true;
  int? port;
  @override
  Future<VelaDownloadSample> sample(int localPort) async {
    port = localPort;
    return succeed
        ? const VelaDownloadSample(ok: true, mbps: 42.5,
            bytes: VelaHttpsDownloadTransport.sampleBytes)
        : const VelaDownloadSample(ok: false);
  }
}

const node = VelaSubscriptionNode(
  name: 'Sample', protocol: 'shadowsocks', server: 'sample.example.test',
  outbound: {
    'type': 'shadowsocks', 'tag': 'selected',
    'server': 'sample.example.test', 'server_port': 443,
    'method': 'aes-128-gcm', 'password': 'do-not-save-or-log',
  },
);

void main() {
  test('isolated HTTPS probe deletes temporary credentials and kills process',
      () async {
    final root = await Directory.systemTemp.createTemp('vela_probe_root_');
    addTearDown(() => root.delete(recursive: true));
    final runner = _Runner();
    final https = _Https();
    final probe = VelaIsolatedNodeProbe(
      coreBinary: 'sing-box.exe', runner: runner,
      httpsProbe: https, tempRoot: root,
    );
    final sample = await probe.measure(node);
    expect(sample.ok, isTrue);
    expect(sample.elapsed, isNotNull);
    expect(https.lastPort, greaterThan(1023));
    expect(runner.process?.killed, isTrue);
    expect(runner.configText, contains('do-not-save-or-log'));
    expect(await root.list().toList(), isEmpty);
  });

  test('failed core self-check cannot claim success and still cleans secrets',
      () async {
    final root = await Directory.systemTemp.createTemp('vela_probe_fail_');
    addTearDown(() => root.delete(recursive: true));
    final runner = _Runner()..checkFails = true;
    final probe = VelaIsolatedNodeProbe(
      coreBinary: 'sing-box.exe', runner: runner,
      httpsProbe: _Https(), tempRoot: root,
    );
    final result = await probe.measure(node);
    expect(result.ok, isFalse);
    expect(result.milliseconds, isNull);
    expect(runner.process, isNull);
    expect(await root.list().toList(), isEmpty);
  });
  test('download measurement uses separate core then deletes profile',
      () async {
    final root = await Directory.systemTemp.createTemp('vela_dl_root_');
    addTearDown(() => root.delete(recursive: true));
    final download = _Download();
    final runner = _Runner();
    final probe = VelaIsolatedNodeProbe(
      coreBinary: 'sing-box.exe', runner: runner,
      httpsProbe: _Https(), downloadTransport: download, tempRoot: root,
    );
    final result = await probe.measureDownload(node);
    expect(result.ok, true);
    expect(result.mbps, 42.5);
    expect(result.bytes, 1048576);
    expect(download.port, greaterThan(0));
    expect(runner.process?.killed, true);
    expect(await root.list().toList(), isEmpty);

    download.succeed = false;
    final failed = await probe.measureDownload(node);
    expect(failed.ok, false);
    expect(failed.mbps, isNull);
    expect(await root.list().toList(), isEmpty);
  });

  test('download transport rejects unsafe local ports', () async {
    const transport = VelaHttpsDownloadTransport();
    expect((await transport.sample(0)).ok, false);
    expect((await transport.sample(65536)).ok, false);
  });

}
