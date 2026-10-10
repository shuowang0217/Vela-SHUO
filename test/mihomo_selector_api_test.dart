import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vela_shuo/src/mihomo/vela_mihomo_selector.dart';

void main() {
  test('authenticated loopback GET and PUT never accept another key',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    var current = 'JP';
    final incoming = <String>[];
    final task = () async {
      await for (final req in server) {
        incoming.add(req.uri.path);
        if (req.uri.path != '/proxies/VELA_SELECT' ||
            req.headers.value(HttpHeaders.authorizationHeader) !=
                'Bearer session-secret') {
          req.response.statusCode = HttpStatus.unauthorized;
          await req.response.close();
          continue;
        }
        if (req.method == 'GET') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'now': current}));
        } else if (req.method == 'PUT') {
          final body = await utf8.decoder.bind(req).join();
          final value = jsonDecode(body) as Map;
          current = value['name'] as String;
          req.response.statusCode = HttpStatus.noContent;
        } else {
          req.response.statusCode = HttpStatus.methodNotAllowed;
        }
        await req.response.close();
      }
    }();
    unawaited(task);
    const api = VelaLoopbackMihomoSelectorApi();
    expect(await api.active(server.port, 'session-secret'), 'JP');
    expect(await api.select(server.port, 'wrong-secret', 'US'), false);
    expect(await api.active(server.port, 'session-secret'), 'JP');
    expect(await api.select(server.port, 'session-secret', 'US'), true);
    expect(await api.active(server.port, 'session-secret'), 'US');
    expect(incoming, everyElement('/proxies/VELA_SELECT'));
    expect(await api.active(0, 'session-secret'), null);
    expect(await api.select(65536, 'session-secret', 'JP'), false);
    await server.close(force: true);
    await task;
  });
}
