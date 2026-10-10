import 'dart:async';
import 'dart:io';

import '../core/vela_core_controller.dart';
import '../subscription/vela_subscription_parser.dart';

/// Actual elapsed time of an HTTPS 204 request through a temporary,
/// node-specific sing-box listener. NOT ICMP ping or download bandwidth.
class VelaLatencySample {
  const VelaLatencySample({required this.ok, this.elapsed});
  final bool ok;
  final Duration? elapsed;
  int? get milliseconds => elapsed?.inMilliseconds;
}

abstract class VelaNodeLatencyProbe {
  Future<VelaLatencySample> measure(VelaSubscriptionNode node);
}

/// Each candidate uses a separate temporary core and loopback port. The
/// active user's proxy core, profile, registry and network routes are not
/// modified. Secrets in temporary profiles are deleted in finally.
class VelaIsolatedNodeProbe implements VelaNodeLatencyProbe {
  VelaIsolatedNodeProbe({
    required this.coreBinary,
    VelaCoreRunner? runner,
    VelaRemoteProbe? httpsProbe,
    Directory? tempRoot,
  }) : _runner = runner ?? const VelaNativeCoreRunner(),
       _https = httpsProbe ?? const VelaHttpsRemoteProbe(),
       _tempRoot = tempRoot;

  final String coreBinary;
  final VelaCoreRunner _runner;
  final VelaRemoteProbe _https;
  final Directory? _tempRoot;

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) async {
    Directory? dir;
    VelaCoreHandle? handle;
    try {
      final portSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4, 0, shared: false,
      ).timeout(const Duration(seconds: 3));
      final port = portSocket.port;
      await portSocket.close();
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
      if (!ready) return const VelaLatencySample(ok: false);
      final watch = Stopwatch()..start();
      final verified = await _https.verify(port)
          .timeout(const Duration(seconds: 21));
      watch.stop();
      if (!verified) return const VelaLatencySample(ok: false);
      return VelaLatencySample(ok: true, elapsed: watch.elapsed);
    } catch (_) {
      // Never log exceptions from untrusted configs or endpoints.
      return const VelaLatencySample(ok: false);
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
          // Cleanup can fail after OS kills the benchmark process.
        }
      }
    }
  }
}
