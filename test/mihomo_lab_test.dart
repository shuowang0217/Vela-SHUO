import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/core/vela_core_controller.dart';
import 'package:vela_shuo/src/mihomo/vela_mihomo_config.dart';
import 'package:vela_shuo/src/mihomo/vela_mihomo_lab_controller.dart';
import 'package:vela_shuo/src/subscription/vela_subscription_parser.dart';

const secret = 'ab0123456789abcdef0123456789abcdef0123456789abcdef';

VelaSubscriptionNode _node(String name, String server) =>
    VelaSubscriptionNode(name: name, protocol: 'ss', server: server,
      outbound: {
        'type': 'shadowsocks', 'tag': 'selected',
        'server': server, 'server_port': 443, 'method': 'aes-128-gcm',
        'password': 'secret-for-unit-test',
      });

class _FakeProcess implements VelaMihomoProcess {
  final Completer<int> done = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => done.future;
  @override
  void kill() {
    killed = true;
    if (!done.isCompleted) { done.complete(0); }
  }
}

class _FakeApi implements VelaMihomoApi {
  String? expectedSecret;
  String? chosen;
  final Set<String> allowed = {};
  bool rejectSwitch = false;
  @override
  Future<String?> active(String secret) async =>
      secret == expectedSecret ? chosen : null;

  @override
  Future<bool> select(String secret, String node) async {
    if (rejectSwitch || secret != expectedSecret ||
        !allowed.contains(node)) { return false; }
    chosen = node;
    return true;
  }
}

class _FakeRunner implements VelaMihomoRunner {
  _FakeRunner(this.api);
  final _FakeApi api;
  _FakeProcess? handle;
  int checks = 0;
  @override
  Future<void> check(String exe, String path, String dir) async {
    checks++;
    final document = jsonDecode(await File(path).readAsString());
    expect(document['external-controller'], '127.0.0.1:20819');
    expect(document['mixed-port'], 20818);
    expect(document['allow-lan'], false);
    api.expectedSecret = document['secret'];
    expect((api.expectedSecret ?? '').length, 64);
    final group = document['proxy-groups'][0];
    api.allowed.addAll(List<String>.from(group['proxies']));
    api.chosen = group['proxies'][0];
  }
  @override
  Future<void> assertPortsFree() async {}
  @override
  Future<VelaMihomoProcess> launch(
      String exe, String path, String dir) async {
    handle = _FakeProcess();
    return handle!;
  }
}

class _FakeProbe implements VelaRemoteProbe {
  bool reachable = true;
  int calls = 0;
  @override
  Future<bool> verify(int port) async {
    expect(port, 20818);
    calls++;
    return reachable;
  }
}

void main() {
  test('safe node conversion, JSON YAML and duplicate tag disambiguation', () {
    final nodes = [_node('JP-01', 'jp1.example'),
      _node('JP-01', 'jp2.example')];
    final config = const VelaMihomoConfigBuilder().build(
        nodes, selectedIndex: 0, secret: secret);
    expect(config.entries.map((e) => e.name).toList(),
        ['JP-01', 'JP-01 (2)']);
    final root = jsonDecode(config.configText);
    expect(root['rules'], ['MATCH,VELA_SELECT']);
    expect(root['proxy-groups'][0]['type'], 'select');
    expect(root['proxy-groups'][0]['proxies'][0], 'JP-01');
    expect(root['proxies'][0]['cipher'], 'aes-128-gcm');
    expect(root['allow-lan'], false);
    expect(root['secret'], secret);
  });

  test('unsupported/out-of-policy proxy rejected without weakening TLS', () {
    const insecure = VelaSubscriptionNode(
      name: 'Bad', protocol: 'vless', server: 'x.example',
      outbound: {
        'type': 'vless', 'server': 'x.example', 'server_port': 443,
        'uuid': 'test-uuid',
        'tls': {'enabled': true, 'insecure': true},
      },
    );
    expect(() => const VelaMihomoConfigBuilder().build(
      [insecure, _node('good', 'good.example')],
      selectedIndex: 0, secret: secret,
    ), throwsFormatException);
    expect(() => const VelaMihomoConfigBuilder().build(
      [_node('good', 'good.example')],
      selectedIndex: 0, secret: 'short',
    ), throwsFormatException);
  });

  test('experimental start, API switch and stop never set Windows proxy',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela-mihomo-test-');
    addTearDown(() => dir.delete(recursive: true));
    final exe = File(dir.path + '/mihomo.exe');
    await exe.writeAsString('stub');
    final api = _FakeApi();
    final runner = _FakeRunner(api);
    final probe = _FakeProbe();
    final lab = VelaMihomoLabController(
      supported: true, bundledBinary: exe.path, stateDirectory: dir,
      runner: runner, api: api, remoteProbe: probe,
    );
    try {
      await lab.initialize();
      expect(lab.hasBinary, true);
      final nodes = [_node('A', 'a.example'), _node('B', 'b.example')];
      expect(await lab.start(nodes, 0), true);
      expect(lab.running, true);
      expect(lab.selectedName, 'A');
      expect(lab.compatibleCount, 2);
      expect(probe.calls, 1);
      expect(await lab.switchNode(1), true);
      expect(lab.selectedName, 'B');
      expect(lab.selectedIndex, 1);
      expect(api.chosen, 'B');
      expect(probe.calls, 2);
      expect(await File(dir.path + '/lab.json').exists(), true);
      await lab.stop();
      expect(lab.running, false);
      expect(runner.handle!.killed, true);
      expect(await File(dir.path + '/lab.json').exists(), false);
    } finally {
      lab.dispose();
    }
  });

  test('switch failure restores previous selector and reports no success',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela-mihomo-fail-');
    addTearDown(() => dir.delete(recursive: true));
    final exe = File(dir.path + '/mihomo.exe');
    await exe.writeAsString('stub');
    final api = _FakeApi();
    final probe = _FakeProbe();
    final lab = VelaMihomoLabController(
      supported: true, bundledBinary: exe.path, stateDirectory: dir,
      runner: _FakeRunner(api), api: api, remoteProbe: probe,
    );
    try {
      await lab.initialize();
      expect(await lab.start(
        [_node('A', 'a.example'), _node('B', 'b.example')], 0), true);
      probe.reachable = false;
      expect(await lab.switchNode(1), false);
      expect(api.chosen, 'A');
      expect(lab.selectedIndex, 0);
      await lab.stop();
      expect(await File(dir.path + '/lab.json').exists(), false);
    } finally { lab.dispose(); }
  });

  test('failed HTTPS verification cleans credentials and child process',
      () async {
    final dir = await Directory.systemTemp.createTemp('vela-mihomo-no-https-');
    addTearDown(() => dir.delete(recursive: true));
    final exe = File(dir.path + '/mihomo.exe');
    await exe.writeAsString('stub');
    final api = _FakeApi();
    final runner = _FakeRunner(api);
    final probe = _FakeProbe()..reachable = false;
    final lab = VelaMihomoLabController(
      supported: true, bundledBinary: exe.path, stateDirectory: dir,
      runner: runner, api: api, remoteProbe: probe,
    );
    try {
      await lab.initialize();
      expect(await lab.start([_node('A','a.example')], 0), false);
      expect(lab.running, false);
      expect(runner.handle?.killed, true);
      expect(await File(dir.path + '/lab.json').exists(), false);
    } finally { lab.dispose(); }
  });
}
