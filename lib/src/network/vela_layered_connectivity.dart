import 'dart:async';
import 'dart:io';

import 'flclash_core_api.dart';

/// On-demand, separated checks. OS DNS resolution is NOT Mihomo's DNS;
/// the HTTPS request does go through native Mihomo with current RULE mode.
/// Neither URLs returned by the core nor credentials enter a log or storage.
class VelaLayeredCheckResult {
  const VelaLayeredCheckResult({
    required this.dnsOk,
    required this.httpsOk,
    required this.dnsDetail,
    required this.httpsDetail,
  });
  final bool dnsOk;
  final bool httpsOk;
  final String dnsDetail;
  final String httpsDetail;
}

class VelaLayeredConnectivityProbe {
  VelaLayeredConnectivityProbe({
    required FlClashCoreApi api,
    Future<List<InternetAddress>> Function(String)? dnsLookup,
    Future<Object?> Function(String, String)? httpsProbe,
  }) : _dns = dnsLookup ?? InternetAddress.lookup,
       _https = httpsProbe ?? api.probe;

  final Future<List<InternetAddress>> Function(String) _dns;
  final Future<Object?> Function(String, String) _https;

  Future<VelaLayeredCheckResult> run() async {
    // Do not use DNS success as proof that the proxy DNS or external route is
    // good. The two independent checks can legitimately disagree.
    var dnsOk = false;
    var httpsOk = false;
    var dns = '系统 DNS 查询失败';
    var https = 'Mihomo HTTPS 检测失败';

    try {
      final addresses = await _dns('example.com')
          .timeout(const Duration(seconds: 4));
      dnsOk = addresses.isNotEmpty;
      if (dnsOk) dns = '系统 DNS 可解析（不代表代理 DNS）';
    } catch (_) {
      dns = '系统 DNS 无法解析或已超时';
    }

    try {
      final reply = await _https(
        'https://cp.cloudflare.com/generate_204', '');
      if (reply is Map) {
        final status = reply['status-code'];
        final failed = reply['error'];
        httpsOk = (status == 204 || status == 200) &&
            (failed == null || failed == '');
        if (httpsOk) {
          https = 'Mihomo HTTPS 可访问';
        } else if (failed == 'timeout') {
          https = 'Mihomo HTTPS 检测超时';
        } else {
          https = 'Mihomo HTTPS 无有效响应';
        }
      }
    } catch (_) {
      https = 'Mihomo HTTPS 调用失败';
    }

    return VelaLayeredCheckResult(
      dnsOk: dnsOk, httpsOk: httpsOk,
      dnsDetail: dns, httpsDetail: https,
    );
  }
}
