import 'dart:async';
import 'dart:io';

/// A bounded, single-request sample through a known local HTTP proxy.
/// This is not a sustained bandwidth test or a promise about other sites.
class VelaDownloadSample {
  const VelaDownloadSample({
    required this.ok, this.mbps, this.bytes = 0, this.reason,
  });
  final bool ok;
  final double? mbps;
  /// Decimal MB/s, matching the user's FlClash-Custom ranking unit.
  double? get megabytesPerSecond => mbps == null ? null : mbps! / 8;
  final int bytes;
  // Safe category from the FlClash core, never a URL, credential or body.
  final String? reason;

  String get failureLabel => switch (reason) {
    'timeout' => '下载超时',
    'http_status' => '下载HTTP异常',
    'network' => '下载网络异常',
    'busy' => '测速内核忙',
    'short_sample' => '下载数据不足',
    'invalid_sample' => '下载数据无效',
    'missing' => '节点不可用',
    'transport_error' => '测速通信超时',
    'no_sample' => '无有效测速数据',
    _ => '下载失败',
  };
}

abstract class VelaDownloadTransport {
  Future<VelaDownloadSample> sample(int localPort);
}

/// No dynamic URLs, redirects, proxy fallback or disabling TLS validation.
/// Download only 1 MiB from Cloudflare's static speed test endpoint. Tests
/// are explicitly requested by the user; the scheduled health scan never
/// downloads this payload.
class VelaHttpsDownloadTransport implements VelaDownloadTransport {
  const VelaHttpsDownloadTransport();

  static const int sampleBytes = 1048576;

  @override
  Future<VelaDownloadSample> sample(int localPort) async {
    if (localPort < 1 || localPort > 65535) {
      return const VelaDownloadSample(ok: false);
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.autoUncompress = false;
    client.findProxy = (_) => 'PROXY 127.0.0.1:$localPort';
    try {
      final uri = Uri.https('speed.cloudflare.com', '/__down',
          {'bytes': sampleBytes.toString()});
      final req = await client.getUrl(uri)
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await req.close()
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok ||
          response.isRedirect ||
          response.headers.value(HttpHeaders.contentEncodingHeader) != null) {
        return const VelaDownloadSample(ok: false);
      }
      if (response.contentLength != -1 &&
          response.contentLength != sampleBytes) {
        return const VelaDownloadSample(ok: false);
      }
      var received = 0;
      final watch = Stopwatch()..start();
      await for (final chunk in response.timeout(
          const Duration(seconds: 8))) {
        received += chunk.length;
        if (received > sampleBytes) {
          return const VelaDownloadSample(ok: false);
        }
      }
      watch.stop();
      if (received != sampleBytes || watch.elapsedMicroseconds <= 0) {
        return const VelaDownloadSample(ok: false);
      }
      final mbps = received * 8 / watch.elapsedMicroseconds;
      if (!mbps.isFinite || mbps <= 0) {
        return const VelaDownloadSample(ok: false);
      }
      return VelaDownloadSample(ok: true, mbps: mbps, bytes: received);
    } catch (_) {
      // Never include response body, endpoint, credentials, or network errors
      // in the user-visible diagnostics.
      return const VelaDownloadSample(ok: false);
    } finally {
      client.close(force: true);
    }
  }
}
