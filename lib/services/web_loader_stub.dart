/// 非 Web 平台的占位实现（仅编译期条件导入兜底）。
library;

Future<Map<String, dynamic>> loadScriptVar(
  String url,
  List<String> varNames,
) async =>
      throw UnsupportedError('仅 Web 平台支持脚本注入');

Future<dynamic> jsonpFetch(String url, String callbackName) async =>
      throw UnsupportedError('仅 Web 平台支持 JSONP');
