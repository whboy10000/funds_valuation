import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'web_loader_stub.dart'
    if (dart.library.js_interop) 'web_loader_web.dart';

export 'web_loader_stub.dart'
    if (dart.library.js_interop) 'web_loader_web.dart';

/// 平台无关的 HTTP GET（内置限频重试）。
///
/// - IO 平台：附带浏览器 User-Agent（东财接口对默认 UA 返回空）与 Referer。
/// - Web 平台：直接 XHR 请求（push2/fundmobapi 等已开 CORS），
///   失败时可调用 [loadScriptVar] 走脚本注入。
/// - 东财接口在密集请求时会返回 400/429，这里自动退避重试 2 次。
Future<String> httpGet(
  String url, {
  String referer = 'https://fund.eastmoney.com/',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final headers = <String, String>{};
  if (!kIsWeb) {
    headers['User-Agent'] =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
    headers['Referer'] = referer;
  }
  var delay = const Duration(milliseconds: 600);
  for (var attempt = 0; ; attempt++) {
    http.Response resp;
    try {
      resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
    } catch (e) {
      // 连接层失败（对端返回空响应/超时等）同样退避重试。
      if (attempt >= 3) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
      continue;
    }
    if (resp.statusCode == 200) {
      // 未声明 charset 的响应按 UTF-8 解码（避免 http 包默认 latin1 导致中文乱码）。
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('charset=')) {
        return resp.body;
      }
      return utf8.decode(resp.bodyBytes, allowMalformed: true);
    }
    final retryable = resp.statusCode == 400 ||
        resp.statusCode == 403 ||
        resp.statusCode == 429 ||
        resp.statusCode >= 500;
    if (!retryable || attempt >= 3) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    await Future<void>.delayed(delay);
    delay *= 2;
  }
}

/// GET 并解析 JSON。
Future<dynamic> httpGetJson(
  String url, {
  String referer = 'https://fund.eastmoney.com/',
}) async =>
      jsonDecode(await httpGet(url, referer: referer));

/// 解析 JSONP 包裹：`cb({...});` → JSON。
dynamic stripJsonp(String text) {
  final s = text.trim();
  final start = s.indexOf('(');
  final end = s.lastIndexOf(')');
  if (start >= 0 && end > start) {
    return jsonDecode(s.substring(start + 1, end));
  }
  return jsonDecode(s);
}

/// 加载一个只包含 `var name = ...;` 赋值的 JS 文件（pingzhongdata）。
///
/// IO 平台直接下载文本再由调用方解析；
/// Web 平台通过 `<script>` 注入，返回各全局变量的值。
Future<Map<String, dynamic>?> loadJsVars(
  String url,
  List<String> varNames,
) async {
  if (kIsWeb) return loadScriptVar(url, varNames);
  return null; // IO 由调用方拿文本自行解析。
}
