import '../smart/vela_node_probe.dart';
import '../smart/vela_download_probe.dart';
import '../subscription/vela_subscription_parser.dart';
import 'flclash_windows_backend.dart';

/// FlClash Go-backed measurements. The original Vela Smart page is unchanged;
/// no separate Vela Mihomo process or proprietary protocol translator is used.
class FlClashGoNodeProbe
    implements VelaNodeLatencyProbe, VelaBatchLatencyProbe,
        VelaNodeDownloadProbe, VelaFullNodeProbe {
  const FlClashGoNodeProbe(this.backend);
  final FlClashWindowsBackend backend;

  @override
  Future<Map<String, VelaLatencySample>> measureBatch(
      List<VelaSubscriptionNode> nodes) async {
    final result = await backend.testLatencies(
        [for (final node in nodes) node.name]);
    return {
      for (final node in nodes)
        node.name: result[node.name] case final int ms when ms > 0
            ? VelaLatencySample(
                ok: true, elapsed: Duration(milliseconds: ms))
            : const VelaLatencySample(ok: false),
    };
  }

  @override
  Future<VelaLatencySample> measure(VelaSubscriptionNode node) async {
    try {
      final ms = await backend.delay(node.name);
      if (ms == null || ms <= 0) {
        return const VelaLatencySample(ok: false);
      }
      return VelaLatencySample(ok: true, elapsed: Duration(milliseconds: ms));
    } catch (_) {
      return const VelaLatencySample(ok: false);
    }
  }

  @override
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) async {
    try {
      final result = await backend.api.invoke('velaTestDownload',
          arguments: {'proxy-name': node.name},
          timeout: const Duration(seconds: 55));
      if (result is! Map || result['ok'] != true ||
          result['mbps'] is! num || result['bytes'] is! num) {
        return const VelaDownloadSample(ok: false);
      }
      final mbps = (result['mbps'] as num).toDouble();
      final bytes = (result['bytes'] as num).toInt();
      // FlClash Go may sample alternate CDN files when Cloudflare is
      // unreachable; validate actual downloaded bytes instead of requiring
      // every provider to return exactly one MiB.
      if (!mbps.isFinite || mbps <= 0 ||
          bytes < 256 * 1024 || bytes > 1024 * 1024) {
        return const VelaDownloadSample(ok: false);
      }
      return VelaDownloadSample(ok: true, mbps: mbps, bytes: bytes);
    } catch (_) {
      return const VelaDownloadSample(ok: false);
    }
  }

  @override
  Future<VelaFullNodeSample> measureBoth(VelaSubscriptionNode node) async {
    final latency = await measure(node);
    final download = await measureDownload(node);
    return VelaFullNodeSample(latency: latency, download: download);
  }
}
