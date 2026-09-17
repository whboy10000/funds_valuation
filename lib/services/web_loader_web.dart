/// Web 平台实现：通过 `<script>` 注入绕过 CORS（脚本标签）。
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// 加载一个赋值全局变量的 JS 文件（如 pingzhongdata/{code}.js），
/// 返回 [varNames] 对应的 Dart 化数据。
Future<Map<String, dynamic>> loadScriptVar(
  String url,
  List<String> varNames,
) async {
  await _injectScript(url);
  final result = <String, dynamic>{};
  for (final name in varNames) {
    final v = globalContext.getProperty(name.toJS);
    result[name] = _normalize(v.dartify());
  }
  return result;
}

/// 通过 JSONP 回调获取数据：全局注册 [callbackName]，注入脚本，回调触发后返回。
Future<dynamic> jsonpFetch(String url, String callbackName) {
  final completer = Completer<dynamic>();
  globalContext.setProperty(
    callbackName.toJS,
    ((JSAny? value) {
      if (!completer.isCompleted) completer.complete(_normalize(value.dartify()));
    }).toJS,
  );
  return _injectScript(url).then((_) {
    globalContext.delete(callbackName.toJS);
    return completer.future.timeout(const Duration(seconds: 12));
  });
}

Future<void> _injectScript(String url) {
  final completer = Completer<void>();
  final script = web.HTMLScriptElement();
  script.src = url;
  script.async = true;
  script.onload = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('脚本加载失败: $url'));
    }
  }).toJS;
  (web.document.head ?? web.document.body!).appendChild(script);
  return completer.future.timeout(const Duration(seconds: 12));
}

/// 把 dartify 的结果归一化为标准 Dart 结构（`Map<String,dynamic>` / List / 原始值）。
dynamic _normalize(Object? v) {
  if (v is Map) {
    return {
      for (final e in v.entries) e.key.toString(): _normalize(e.value),
    };
  }
  if (v is List) return v.map(_normalize).toList();
  return v;
}
