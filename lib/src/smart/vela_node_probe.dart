import 'dart:async';
import 'dart:io';

import '../core/vela_core_controller.dart';
import '../subscription/vela_subscription_parser.dart';
import 'vela_download_probe.dart';

class VelaLatencySample {
  const VelaLatencySample({required this.ok, this.elapsed});
  final bool ok;
  final Duration? elapsed;
  int? get milliseconds => elapsed?.inMilliseconds;
}

abstract class VelaNodeLatencyProbe {
  Future<VelaLatencySample> measure(VelaSubscriptionNode node);
}

abstract class VelaNodeDownloadProbe {
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node);
}

/// Each measurement uses a separate sing-box process, disposable config and
/// random loopback port. The active Windows system proxy is never modified.
/// Both latency and sample-download measurements use the same cleanup path.
class VelaIsolatedNodeProbe
    implements VelaNodeLatencyProbe, VelaNodeDownloadProbe {
  VelaIsolatedNodeProbe({
    required this.coreBinary,
    VelaCoreRunner? runner,
    VelaRemoteProbe? httpsProbe,
    VelaDownloadTransport? downloadTransport,
    Directory? tempRoot,
  }) : _runner = runner ?? const VelaNativeCoreRunner(),
       _https = httpsProbe ?? const VelaHttpsRemoteProbe(),
       _download = downloadTransport ?? const VelaHttpsDownloadTransport(),
       _tempRoot = tempRoot;

  final String coreBinary;
  final VelaCoreRunner _runner;
  final VelaRemoteProbe _https;
  final VelaDownloadTransport _download;
  final Directory? _tempRoot;

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) =>
      _withCore<VelaLatencySample>(node, (port) async {
        final watch = Stopwatch()..start();
        final verified = await _https.verify(port)
            .timeout(const Duration(seconds: 21));
        watch.stop();
        return verified
            ? VelaLatencySample(ok: true, elapsed: watch.elapsed)
            : const VelaLatencySample(ok: false);
      }, const VelaLatencySample(ok: false));

  @override
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) =>
      _withCore<VelaDownloadSample>(node, (port) =>
        _download.sample(port).timeout(const Duration(seconds: 27)),
        const VelaDownloadSample(ok: false));

  Future<T> _withCore<T>(VelaSubscriptionNode node,
      Future<T> Function(int port) sample, T failed) async {
    Directory? dir;
    VelaCoreHandle? handle;
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, shared: false,
      ).timeout(const Duration(seconds: 3));
      final port = socket.port;
      await socket.close();
      dir = await (_tempRoot == null
          ? Directory.systemTemp.createTemp('vela-benchmark-')
          : _tempRoot.createTemp('vela-benchmark-'))
          .timeout(const Duration(seconds: 3));
      final config = File('${dir.path}${Platform.pathSeparator}profile.json');
      await config.writeAsString(
        VelaSubscriptionParser.buildConfig(node, port: port),
        flush: true,
      );
      await _runner.check(coreBinary, config.path)
          .timeout(const Duration(seconds: 12));
      await _runner.assertPortFree(port)
          .timeout(const Duration(seconds: 3));
      handle = await _runner.launch(coreBinary, config.path)
          .timeout(const Duration(seconds: 4));
      final ready = await _runner.awaitLocalListener(port)
          .timeout(const Duration(seconds: 10));
      if (!ready) { return failed; }
      return await sample(port);
    } catch (_) {
      return failed;
    } finally {
      handle?.kill();
      if (handle != null) {
        try {
          await handle.exitCode.timeout(const Duration(seconds: 2));
        } catch (_) {
          handle.kill();
        }
      }
      if (dir != null) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // An abnormal OS kill can leave a temporary config.
        }
      }
    }
  }
}
