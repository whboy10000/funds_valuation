import '../models.dart';
import 'http_client.dart';

/// 东财行情接口（push2 系列，支持 A股/港股/美股/指数/板块混合批量查询）。
class MarketApi {
  static const _common = 'fltt=2&invt=2';

  /// A股主要指数 secid 列表。
  static const aIndices = <(String, String)>[
    ('1.000001', '上证指数'),
    ('0.399001', '深证成指'),
    ('0.399006', '创业板指'),
    ('1.000300', '沪深300'),
    ('1.000688', '科创50'),
    ('1.000905', '中证500'),
    ('1.000016', '上证50'),
  ];

  /// 港股主要指数（恒生科技市场号为 124，恒生/国企为 100，
  /// 港股通系列为中证指数、市场号 2）。
  static const hkIndices = <(String, String)>[
    ('100.HSI', '恒生指数'),
    ('124.HSTECH', '恒生科技'),
    ('100.HSCEI', '国企指数'),
    ('2.931637', '港股通互联网'),
    ('2.931573', '港股通科技'),
    ('2.931454', '港股通消费'),
    ('2.931250', '港股通创新药'),
    ('2.930914', '港股通高股息'),
    ('2.931233', '港股通央企红利'),
    ('124.HSHCI', '恒生医疗保健'),
    ('2.932069', '港股通医疗主题'),
    ('2.930967', '港股通信息C'),
    ('2.931239', '港股通汽车'),
  ];

  /// 全球指数 secid 列表。
  static const globalIndices = <(String, String)>[
    ('100.NDX', '纳斯达克100'),
    ('100.DJIA', '道琼斯'),
    ('100.SPX', '标普500'),
    ('100.N225', '日经225'),
    ('100.KS11', '韩国KOSPI'),
    ('100.FTSE', '英国富时100'),
  ];

  /// 行情主机：主域偶发限频/空响应，依次回退到数字镜像与延迟域。
  static const _quoteHosts = [
    'push2.eastmoney.com',
    '29.push2.eastmoney.com',
    'push2delay.eastmoney.com',
  ];

  /// 批量实时行情：secid → (价格, 涨跌幅%, 涨跌额)。
  /// 一次请求支持混合市场（1./0. 沪深、116. 港、105/106/107. 美、100. 全球指数）。
  /// 部分指数（如恒生科技）在批量请求中偶发被丢弃，这里对缺失项自动补拉。
  static Future<Map<String, Quote>> quotes(List<String> secids) async {
    if (secids.isEmpty) return {};
    final out = <String, Quote>{};
    // secid 过多时分组请求，单次上限 60。
    for (var i = 0; i < secids.length; i += 60) {
      final group = secids.sublist(i, i + 60 > secids.length ? secids.length : i + 60);
      out.addAll(await _quotesGroup(group));
    }
    // 缺失项先批量重拉一轮（多数被丢弃的 secid 一轮即可找回），
    // 仍有缺失再逐个补拉（最多 8 个，避免请求风暴）。
    var missing = secids.where((s) => !out.containsKey(s)).take(8).toList();
    if (missing.isNotEmpty && missing.length < secids.length) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < missing.length; i += 60) {
        try {
          out.addAll(await _quotesGroup(
              missing.sublist(i, i + 60 > missing.length ? missing.length : i + 60)));
        } catch (_) {}
      }
      missing = missing.where((s) => !out.containsKey(s)).toList();
      for (final s in missing) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        try {
          out.addAll(await _quotesGroup([s]));
        } catch (_) {}
      }
    }
    return out;
  }

  /// 单组批量行情，多主机回退；全部失败时抛出最后一个异常。
  static Future<Map<String, Quote>> _quotesGroup(List<String> group) async {
    Object? lastErr;
    for (final host in _quoteHosts) {
      try {
        final url = 'https://$host/api/qt/ulist.np/get'
            '?secids=${group.join(',')}&fields=f2,f3,f4,f12,f85,f116&$_common';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final out = <String, Quote>{};
        for (final d in (data?['data']?['diff'] as List?) ?? const []) {
          final code = '${d['f12']}';
          if (code.isEmpty) continue;
          out[_fullSecid(code, group)] = Quote(
            price: _num(d['f2']),
            pct: _num(d['f3']),
            change: _num(d['f4']),
            // f85 总股本/份额（份），f116 总市值（元）；ETF 场内即实时规模。
            share: _num(d['f85']),
            totalWorth: _num(d['f116']),
          );
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) throw Exception('行情获取失败: $lastErr');
    return {};
  }

  /// ulist 返回的 f12 是纯代码，需还原为带市场前缀的 secid。
  static String _fullSecid(String code, List<String> group) {
    for (final g in group) {
      if (g.toLowerCase().endsWith('.${code.toLowerCase()}')) return g;
    }
    return code;
  }

  /// 分时走势（当日），[secid] 支持指数/板块/个股。
  /// 返回 (分时点, 昨收价)；昨收价用于计算涨跌基线。
  /// push2his 被限频时回退到延迟域。
  static Future<({List<TrendPoint> points, double preClose})> trend(
      String secid) async {
    Object? lastErr;
    for (final host in const [
      'push2his.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final url = 'https://$host/api/qt/stock/trends2/get?secid=$secid'
            '&fields1=f1,f2,f3,f7,f8&fields2=f51,f53&iscr=0&ndays=1';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final list = (data?['data']?['trends'] as List?) ?? const [];
        final preClose = _num(data?['data']?['preClose']);
        final out = <TrendPoint>[];
        for (final row in list) {
          final parts = '$row'.split(',');
          if (parts.length < 2) continue;
          final t = parts[0].split(' ');
          out.add(TrendPoint(t.length > 1 ? t[1] : parts[0],
              double.tryParse(parts[1]) ?? 0));
        }
        if (out.isNotEmpty) return (points: out, preClose: preClose);
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('分时获取失败: $lastErr');
  }

  /// 场内基金（ETF/LOF）实时行情排行：以实时成交价涨跌幅排序，
  /// 非昨日净值口径。全市场约 1600 只，分页拉取（单页上限 100）。
  static Future<List<FundRankItem>> etfList() async {
    Object? lastErr;
    for (final host in const [
      '29.push2.eastmoney.com',
      '17.push2.eastmoney.com',
      'push2.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final list = await _etfOn(host);
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) throw Exception('场内基金获取失败: $lastErr');
    return const [];
  }

  static Future<List<FundRankItem>> _etfOn(String host) async {
    final out = <FundRankItem>[];
    var page = 1;
    var total = 1 << 30;
    while ((page - 1) * 100 < total && page <= 20) {
      final url = 'https://$host/api/qt/clist/get?pn=$page&pz=100&po=1&np=1'
          '&$_common&fid=f3&fs=b:MK0021,b:MK0022,b:MK0023,b:MK0024'
          '&fields=f2,f3,f12,f14';
      final data = await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
      total = (data?['data']?['total'] as num?)?.toInt() ?? 0;
      final diff = (data?['data']?['diff'] as List?) ?? const [];
      if (diff.isEmpty) break;
      for (final d in diff) {
        out.add(FundRankItem(
          code: '${d['f12']}',
          name: '${d['f14'] ?? d['f12']}',
          navDate: '', // 场内实时，无净值日期
          nav: _num(d['f2']),
          pct: _num(d['f3']),
        ));
      }
      page++;
      // 翻页节流，降低触发频控的概率。
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  /// 日 K 收盘序列（不复权），时间正序：(yyyy-MM-dd, 收盘价)。
  /// 用于场内基金每日规模 = 份额 × 收盘价。
  static Future<List<(String, double)>> klineDaily(String secid,
      {int lmt = 365}) async {
    Object? lastErr;
    for (final host in const [
      'push2his.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final url = 'https://$host/api/qt/stock/kline/get?secid=$secid'
            '&fields1=f1,f2,f3&fields2=f51,f53&klt=101&fqt=0'
            '&lmt=$lmt&end=20500101&$_common';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final list = (data?['data']?['klines'] as List?) ?? const [];
        final out = <(String, double)>[];
        for (final row in list) {
          final p = '$row'.split(',');
          if (p.length < 2) continue;
          final close = double.tryParse(p[1]);
          if (close != null && close > 0) out.add((p[0], close));
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('日K获取失败: $lastErr');
  }

  /// 场内基金（ETF/LOF）规模要素：单只 stock/get 接口取
  /// 价格(f43)/份额(f84)/总市值(f116)。
  /// 注意：ulist 批量接口对 ETF 的 f84/f85 会返回错误值，必须用本接口。
  static Future<Quote> etfInfo(String secid) async {
    Object? lastErr;
    for (final host in _quoteHosts) {
      try {
        final url = 'https://$host/api/qt/stock/get?secid=$secid'
            '&fields=f43,f84,f116&$_common';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final d = data?['data'];
        if (d == null) continue;
        final q = Quote(
          price: _num(d['f43']),
          pct: 0,
          change: 0,
          share: _num(d['f84']),
          totalWorth: _num(d['f116']),
        );
        if (q.price > 0 && q.share > 0) return q;
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('场内信息获取失败: ${lastErr ?? "无数据"}');
  }

  /// 板块列表：[type] 2=行业、3=概念。
  /// 分页拉取全量（单页上限 100， pz 过大时服务端会截断，导致只见正值板块）。
  /// 单主机偶发空响应/限频导致列表为空，故做多主机回退。
  static Future<List<Sector>> sectors({required int type}) async {
    Object? lastErr;
    for (final host in const [
      '29.push2.eastmoney.com',
      '17.push2.eastmoney.com',
      'push2.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final list = await _sectorsOn(host, type);
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) throw Exception('板块获取失败: $lastErr');
    return const [];
  }

  static Future<List<Sector>> _sectorsOn(String host, int type) async {
    final out = <Sector>[];
    var page = 1;
    var total = 1 << 30;
    while ((page - 1) * 100 < total && page <= 20) {
      final url = 'https://$host/api/qt/clist/get?pn=$page&pz=100&po=1&np=1'
          '&$_common&fid=f3&fs=m:90+t:$type+f:!50'
          '&fields=f2,f3,f8,f12,f14,f62,f104,f105,f128,f136';
      final data = await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
      total = (data?['data']?['total'] as num?)?.toInt() ?? 0;
      final diff = (data?['data']?['diff'] as List?) ?? const [];
      if (diff.isEmpty) break;
      for (final d in diff) {
        out.add(Sector(
          code: '${d['f12']}',
          name: '${d['f14']}',
          pct: _num(d['f3']),
          turnover: _num(d['f8']),
          netInflow: _num(d['f62']),
          upCount: _num(d['f104']).round(),
          downCount: _num(d['f105']).round(),
          leadStock: '${d['f128'] ?? ''}',
          leadStockPct: _num(d['f136']),
        ));
      }
      page++;
      // 翻页节流，降低触发频控的概率。
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  /// 板块成分股实时行情（fs=b:CODE f:!50）。
  /// push2 数字镜像与主域对该 fs 支持最好（延迟域只返回领涨股摘要），
  /// 单主机偶发空响应/限频，故做多主机回退；
  /// 延迟域对该 fs 解析异常（返回全市场），仅作末位回退并用总数上限拦截。
  static Future<List<SectorMember>> sectorMembers(String bkCode) async {
    Object? lastErr;
    const hosts = <(String, int)>[
      ('29.push2.eastmoney.com', 1 << 30),
      ('push2.eastmoney.com', 1 << 30),
      ('push2delay.eastmoney.com', 6000),
    ];
    for (final (host, maxTotal) in hosts) {
      try {
        final list = await _sectorMembersOn(host, bkCode, maxTotal);
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null) throw Exception('成分股获取失败: $lastErr');
    return const [];
  }

  static Future<List<SectorMember>> _sectorMembersOn(
      String host, String bkCode, int maxTotal) async {
    final out = <SectorMember>[];
    var page = 1;
    var total = 1 << 30;
    while ((page - 1) * 100 < total && page <= 80) {
      final url = 'https://$host/api/qt/clist/get?pn=$page&pz=100&po=1&np=1'
          '&$_common&fid=f3&fs=b:$bkCode%20f:!50'
          '&fields=f2,f3,f8,f12,f14,f62';
      final data = await httpGetJson(url, referer: 'https://data.eastmoney.com/');
      final d = data?['data'];
      if (d == null) throw Exception('empty response');
      total = (d['total'] as num?)?.toInt() ?? 0;
      if (total > maxTotal) throw Exception('响应异常 total=$total');
      final diff = (d['diff'] as List?) ?? const [];
      if (diff.isEmpty) break;
      for (final e in diff) {
        final code = '${e['f12']}';
        // 过滤非常规代码（如期权 HO2609-P-2900 等）。
        if (!RegExp(r'^\d{5,6}$').hasMatch(code)) continue;
        out.add(SectorMember(
          code: code,
          name: '${e['f14']}',
          price: _num(e['f2']),
          pct: _num(e['f3']),
          turnover: _num(e['f8']),
          netInflow: _num(e['f62']),
        ));
      }
      page++;
      // 翻页节流，降低触发频控的概率。
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  /// 全市场涨跌分布（上涨/平盘/下跌 及分档家数）。
  static Future<MarketBreadth?> breadth() async {
    final url = 'https://push2ex.eastmoney.com/getTopicZDFenBu'
        '?ut=7eea3edcaed734bea9cbfc24409ed989&dpt=wz.ztzt';
    final data = await httpGetJson(url);
    final list = (data?['data']?['fenbu'] as List?) ?? const [];
    var up = 0, down = 0, flat = 0;
    final buckets = <MapEntry<int, int>>[];
    for (final e in list) {
      if (e is! Map) continue;
      e.forEach((k, v) {
        final key = int.tryParse('$k');
        final val = int.tryParse('$v') ?? 0;
        if (key == null) return;
        if (key < 0) {
          down += val;
        } else if (key > 0) {
          up += val;
        } else {
          flat = val;
        }
        buckets.add(MapEntry(key, val));
      });
    }
    buckets.sort((a, b) => a.key.compareTo(b.key));
    if (up + down + flat == 0) return null;
    return MarketBreadth(up: up, down: down, flat: flat, buckets: buckets);
  }

  static double _num(Object? v) {
    final s = '$v';
    return double.tryParse(s) ?? 0;
  }
}

/// 一条实时行情。
class Quote {
  const Quote({
    required this.price,
    required this.pct,
    required this.change,
    this.share = 0,
    this.totalWorth = 0,
  });

  final double price;
  final double pct;
  final double change;

  /// 总股本 / 份额（份）；ETF 场内即流通份额规模口径。
  final double share;

  /// 总市值（元）；ETF 场内即实时基金规模。
  final double totalWorth;
}
