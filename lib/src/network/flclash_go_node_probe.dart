import '../smart/vela_node_probe.dart';
import '../smart/vela_download_probe.dart';
import '../subscription/vela_subscription_parser.dart';
import 'flclash_windows_backend.dart';
import 'flclash_core_api.dart';

/// FlClash Go-backed measurements. The original Vela Smart page is unchanged;
/// no separate Vela Mihomo process or proprietary protocol translator is used.
class FlClashGoNodeProbe
    implements VelaNodeLatencyProbe, VelaBatchLatencyProbe,
        VelaNodeDownloadProbe, VelaDownloadVerificationProbe, VelaFullNodeProbe {
  const FlClashGoNodeProbe(this.backend);
  final FlClashWindowsBackend backend;

  @override
  Future<Map<String, VelaLatencySample>> measureBatch(
      List<VelaSubscriptionNode> nodes) async {
    final result = await backend.testLatencies(
        [for (final node in nodes) node.name]);
    return {
      for (final node in nodes)
        node.name: (result[node.name] ?? 0) > 0
            ? VelaLatencySample(
                ok: true,
                elapsed: Duration(milliseconds: result[node.name]!))
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
  Future<VelaDownloadSample> measureDownload(VelaSubscriptionNode node) =>
      _sampleDownload(node, verify: false);

  @override
  Future<VelaDownloadSample> verifyDownload(
      VelaSubscriptionNode node, VelaDownloadSample preliminary) =>
      _sampleDownload(node, verify: true, source: preliminary.source);

  Future<VelaDownloadSample> _sampleDownload(
      VelaSubscriptionNode node, {required bool verify, String? source}) async {
    try {
      final arguments = <String, String>{
        'proxy-name': node.name,
        'mode': verify ? 'verify' : 'quick',
      };
      if (verify && source != null) arguments['source'] = source;
      final result = await backend.api.invoke('velaTestDownload',
          arguments: arguments,
          timeout: const Duration(seconds: 30));
      // The native endpoint reports a safe reason code for a failed probe.
      // Keep it for the node card instead of hiding every failure behind
      // "下载失败". This method is shared by single and all-node scans.
      if (result is Map && result['ok'] == false) {
        final reason = result['reason'];
        return VelaDownloadSample(
            ok: false, reason: reason is String ? reason : null);
      }
      if (result is! Map || result['ok'] != true ||
          result['mbps'] is! num || result['bytes'] is! num) {
        return const VelaDownloadSample(ok: false, reason: 'invalid_sample');
      }
      final mbps = (result['mbps'] as num).toDouble();
      final bytes = (result['bytes'] as num).toInt();
      // FlClash Go may sample alternate CDN files when Cloudflare is
      // unreachable; validate actual downloaded bytes instead of requiring
      // every provider to return exactly one MiB.
      if (!mbps.isFinite || mbps <= 0 ||
          bytes < 64 * 1024 || bytes > 16 * 1024 * 1024) {
        return const VelaDownloadSample(ok: false, reason: 'short_sample');
      }
      final nativeSource = result['source'];
      final measuredSource = nativeSource is String &&
          const {'cloudflare', 'cachefly', 'ovh'}.contains(nativeSource)
          ? nativeSource : null;
      return VelaDownloadSample(
          ok: true, mbps: mbps, bytes: bytes,
          verified: verify, source: measuredSource);
    } on FlClashCoreFailure catch (error) {
      return VelaDownloadSample(ok: false,
          reason: error.code == 'transport_error'
              ? 'transport_error' : 'network');
    } catch (_) {
      return const VelaDownloadSample(ok: false, reason: 'transport_error');
    }
  }

  @override
  Future<VelaFullNodeSample> measureBoth(VelaSubscriptionNode node) async {
    final latency = await measure(node);
    final download = await measureDownload(node);
    return VelaFullNodeSample(latency: latency, download: download);
  }
}
