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

  /// 全球指数 secid 列表（市场号 100 为东财全球指数板块）。
  /// 覆盖北美、欧洲、亚太、拉美主要基准指数；全部经实测 ulist + stock/get 可用。
  static const globalIndices = <(String, String)>[
    // —— 北美 ——
    ('100.DJIA', '道琼斯'),
    ('100.SPX', '标普500'),
    ('100.NDX', '纳斯达克100'),
    ('100.TSX', '加拿大S&P/TSX'),
    ('100.MXX', '墨西哥BOLSA'),
    // —— 欧洲 ——
    ('100.FTSE', '英国富时100'),
    ('100.MCX', '英国富时250'),
    ('100.GDAXI', '德国DAX30'),
    ('100.FCHI', '法国CAC40'),
    ('100.SX5E', '欧洲斯托克50'),
    ('100.SXXP', '欧洲斯托克600'),
    ('100.IBEX', '西班牙IBEX35'),
    ('100.MIB', '富时意大利MIB'),
    ('100.AEX', '荷兰AEX'),
    ('100.SSMI', '瑞士SMI'),
    // —— 亚太 ——
    ('100.N225', '日经225'),
    ('100.KS11', '韩国KOSPI'),
    ('100.TWII', '台湾加权'),
    ('100.STI', '富时新加坡海峡时报'),
    ('100.SENSEX', '印度孟买SENSEX'),
    ('100.AORD', '澳大利亚普通股'),
    ('100.AS51', '澳大利亚标普200'),
    // —— 拉美 ——
    ('100.BVSP', '巴西BOVESPA'),
  ];

  /// 指数排行 · A 股主流指数清单：(secid, 名称, 分组)。
  /// 分组：宽基 / 风格 / 行业；覆盖主流宽基规模、策略风格与 30+ 行业主题。
  /// secid 已逐个实测可用（930/931/932/H30 开头为中证指数、市场号 2）。
  static const indexRankA = <(String, String, String)>[
    // —— 宽基规模 ——
    ('1.000001', '上证指数', '宽基'),
    ('0.399001', '深证成指', '宽基'),
    ('0.399006', '创业板指', '宽基'),
    ('0.399673', '创业板50', '宽基'),
    ('0.399850', '深证50', '宽基'),
    ('1.000688', '科创50', '宽基'),
    ('1.000698', '科创100', '宽基'),
    ('1.000680', '科创综指', '宽基'),
    ('0.899050', '北证50', '宽基'),
    ('1.000016', '上证50', '宽基'),
    ('1.000010', '上证180', '宽基'),
    ('0.399330', '深证100', '宽基'),
    ('1.000300', '沪深300', '宽基'),
    ('1.000510', '中证A500', '宽基'),
    ('2.930050', '中证A50', '宽基'),
    ('1.000903', '中证A100', '宽基'),
    ('1.000904', '中证200', '宽基'),
    ('1.000905', '中证500', '宽基'),
    ('1.000852', '中证1000', '宽基'),
    ('2.932000', '中证2000', '宽基'),
    ('0.399303', '国证2000', '宽基'),
    ('1.000906', '中证800', '宽基'),
    ('1.000985', '中证全指', '宽基'),
    // —— 策略风格 ——
    ('1.000015', '上证红利', '风格'),
    ('1.000922', '中证红利', '风格'),
    ('2.H30269', '红利低波', '风格'),
    ('0.399550', '央视50', '风格'),
    ('1.000926', '中证央企', '风格'),
    ('1.000927', '央企100', '风格'),
    // —— 行业 / 主题 ——
    ('0.399986', '中证银行', '行业'),
    ('0.399975', '证券公司', '行业'),
    ('0.399809', '保险主题', '行业'),
    ('1.000992', '全指金融', '行业'),
    ('0.399393', '国证地产', '行业'),
    ('1.000819', '有色金属', '行业'),
    ('0.399998', '中证煤炭', '行业'),
    ('2.930606', '中证钢铁', '行业'),
    ('2.931009', '建筑材料', '行业'),
    ('2.930608', '中证基建', '行业'),
    ('1.000812', '细分机械', '行业'),
    ('1.000813', '细分化工', '行业'),
    ('2.930697', '家用电器', '行业'),
    ('1.000807', '食品饮料', '行业'),
    ('0.399997', '中证白酒', '行业'),
    ('1.000932', '中证消费', '行业'),
    ('1.000808', '医药生物', '行业'),
    ('1.000991', '全指医药', '行业'),
    ('0.399989', '中证医疗', '行业'),
    ('2.931484', 'CS医药创新', '行业'),
    ('1.000949', '中证农业', '行业'),
    ('0.399971', '中证传媒', '行业'),
    ('0.399967', '中证军工', '行业'),
    ('0.399973', '中证国防', '行业'),
    ('2.930652', 'CS电子', '行业'),
    ('2.930651', 'CS计算机', '行业'),
    ('2.931865', '中证半导', '行业'),
    ('0.980017', '国证芯片', '行业'),
    ('2.930713', 'CS人工智能', '行业'),
    ('2.931160', '通信设备', '行业'),
    ('0.399994', '信息安全', '行业'),
    ('2.931151', '光伏产业', '行业'),
    ('0.399808', '中证新能', '行业'),
    ('0.399976', 'CS新能车', '行业'),
    ('1.000827', '中证环保', '行业'),
    ('2.930633', '中证旅游', '行业'),
    ('1.000986', '全指能源', '行业'),
    ('1.000995', '全指公用', '行业'),
  ];

  /// 指数排行 · 港股主流指数清单（分组恒为「港股」）。
  static const indexRankHK = <(String, String, String)>[
    ('100.HSI', '恒生指数', '港股'),
    ('100.HSCEI', '国企指数', '港股'),
    ('124.HSCCI', '红筹指数', '港股'),
    ('124.HSCI', '恒生综合', '港股'),
    ('124.HSTECH', '恒生科技', '港股'),
    ('124.HSHCI', '恒生医疗保健', '港股'),
    ('124.HSP', '恒生地产', '港股'),
    ('2.931574', '港股科技', '港股'),
    ('2.931637', '港股通互联网', '港股'),
    ('2.931454', '港股通消费', '港股'),
    ('2.931250', '港股通创新药', '港股'),
    ('2.932069', '港股通医疗主题', '港股'),
    ('2.930914', '港股通高股息', '港股'),
    ('2.931233', '港股通央企红利', '港股'),
    ('2.930967', '港股通信息C', '港股'),
    ('2.931239', '港股通汽车', '港股'),
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
  /// 非昨日净值口径。返回涨跌两端头部（约 600 只），
  /// 多主机尝试并择优（取条数最多的一轮）。
  static Future<List<FundRankItem>> etfList() async {
    Object? lastErr;
    List<FundRankItem>? best;
    for (final host in const [
      '29.push2.eastmoney.com',
      '17.push2.eastmoney.com',
      'push2.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final list = await _etfOn(host);
        if (list.length >= 300) return list; // 完整一轮，直接使用。
        if (best == null || list.length > best.length) best = list;
      } catch (e) {
        lastErr = e;
      }
    }
    if (best != null && best.isNotEmpty) return best;
    if (lastErr != null) throw Exception('场内基金获取失败: $lastErr');
    return const [];
  }

  static Future<List<FundRankItem>> _etfOn(String host) async {
    // 头尾双向各 3 页（约 600 只）：涨幅榜头部 + 跌幅榜头部，
    // 涨跌两端全覆盖；并行请求（串行翻页在移动端网络下过慢）。
    final specs = [
      for (final po in const [1, 0])
        for (var page = 1; page <= 3; page++) (po, page),
    ];
    Future<List<dynamic>> fetch(int po, int page) async {
      try {
        final url = 'https://$host/api/qt/clist/get?pn=$page&pz=100&po=$po&np=1'
            '&$_common&fid=f3&fs=b:MK0021,b:MK0022,b:MK0023,b:MK0024'
            '&fields=f2,f3,f12,f14';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        return (data?['data']?['diff'] as List?) ?? const [];
      } catch (_) {
        return const []; // 单页失败跳过，稍后补拉。
      }
    }

    final results = <List<dynamic>>[];
    results.addAll(await Future.wait(
        [for (final s in specs) fetch(s.$1, s.$2)]));
    // 并发易触发频控丢页：对空页串行补拉一轮。
    for (var i = 0; i < specs.length; i++) {
      if (results[i].isNotEmpty) continue;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      results[i] = await fetch(specs[i].$1, specs[i].$2);
    }
    final out = <FundRankItem>[];
    for (final diff in results) {
      for (final d in diff) {
        out.add(FundRankItem(
          code: '${d['f12']}',
          name: '${d['f14'] ?? d['f12']}',
          navDate: '', // 场内实时，无净值日期
          nav: _num(d['f2']),
          pct: _num(d['f3']),
        ));
      }
    }
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  /// 指数实时排行：对内置主流指数清单（[indexRankA]/[indexRankHK]）
  /// 做一次批量行情查询，丢弃未返回或停盘无价的项，按清单原顺序返回。
  /// 排序与分组过滤由页面端完成。
  static Future<List<IndexRankItem>> indexRank(
      List<(String, String, String)> metas) async {
    final qs = await quotes([for (final m in metas) m.$1]);
    final out = <IndexRankItem>[];
    for (final m in metas) {
      final q = qs[m.$1];
      if (q == null || q.price <= 0) continue;
      out.add(IndexRankItem(
        secid: m.$1,
        name: m.$2,
        group: m.$3,
        price: q.price,
        pct: q.pct,
      ));
    }
    return out;
  }

  /// 指数 / 个股单只实时详情：开高低收、振幅、量额、换手、市值等。
  /// 港股与部分指数不提供换手/市值字段，对应值返回 0（页面端按 0 隐藏）。
  static Future<IndexQuoteDetail> indexQuoteDetail(String secid) async {
    Object? lastErr;
    for (final host in _quoteHosts) {
      try {
        final url = 'https://$host/api/qt/stock/get?secid=$secid'
            '&fields=f43,f44,f45,f46,f47,f48,f50,f57,f58,f60,f86,'
            'f116,f117,f168,f169,f170,f171,f174,f175&$_common';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final d = data?['data'];
        if (d == null) continue;
        return IndexQuoteDetail(
          code: '${d['f57'] ?? ''}',
          name: '${d['f58'] ?? ''}',
          price: _num(d['f43']),
          high: _num(d['f44']),
          low: _num(d['f45']),
          open: _num(d['f46']),
          volume: _num(d['f47']),
          amount: _num(d['f48']),
          volumeRatio: _num(d['f50']),
          preClose: _num(d['f60']),
          quoteTimeMs: _num(d['f86']).toInt(),
          totalMv: _num(d['f116']),
          floatMv: _num(d['f117']),
          turnoverRate: _num(d['f168']),
          change: _num(d['f169']),
          pct: _num(d['f170']),
          amplitude: _num(d['f171']),
          high52w: _num(d['f174']),
          low52w: _num(d['f175']),
        );
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('指数详情获取失败: $lastErr');
  }

  /// 日 K OHLC（不复权），时间正序。用于指数详情的历史区间统计与走势图。
  static Future<List<IndexKline>> indexKline(String secid,
      {int lmt = 400}) async {
    Object? lastErr;
    for (final host in const [
      'push2his.eastmoney.com',
      'push2delay.eastmoney.com',
    ]) {
      try {
        final url = 'https://$host/api/qt/stock/kline/get?secid=$secid'
            '&fields1=f1,f2,f3&fields2=f51,f52,f53,f54,f55,f56,f57'
            '&klt=101&fqt=0&lmt=$lmt&end=20500101&$_common';
        final data =
            await httpGetJson(url, referer: 'https://quote.eastmoney.com/');
        final list = (data?['data']?['klines'] as List?) ?? const [];
        final out = <IndexKline>[];
        for (final row in list) {
          final p = '$row'.split(',');
          if (p.length < 7) continue;
          final k = IndexKline(
            date: p[0],
            open: double.tryParse(p[1]) ?? 0,
            close: double.tryParse(p[2]) ?? 0,
            high: double.tryParse(p[3]) ?? 0,
            low: double.tryParse(p[4]) ?? 0,
            volume: double.tryParse(p[5]) ?? 0,
            amount: double.tryParse(p[6]) ?? 0,
          );
          if (k.close > 0) out.add(k);
        }
        if (out.isNotEmpty) return out;
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('日K获取失败: $lastErr');
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

/// 指数排行榜单项（实时口径）。
class IndexRankItem {
  const IndexRankItem({
    required this.secid,
    required this.name,
    required this.group,
    required this.price,
    required this.pct,
  });

  /// 东财 secid，如 1.000300 / 100.HSI。
  final String secid;

  /// 指数名称。
  final String name;

  /// 分组：宽基 / 风格 / 行业 / 港股。
  final String group;

  /// 最新点位。
  final double price;

  /// 实时涨跌幅 %。
  final double pct;
}

/// 指数单只实时详情（stock/get 全字段口径）。
class IndexQuoteDetail {
  const IndexQuoteDetail({
    required this.code,
    required this.name,
    required this.price,
    required this.open,
    required this.high,
    required this.low,
    required this.preClose,
    required this.change,
    required this.pct,
    required this.amplitude,
    required this.volume,
    required this.amount,
    required this.volumeRatio,
    required this.turnoverRate,
    required this.totalMv,
    required this.floatMv,
    required this.high52w,
    required this.low52w,
    required this.quoteTimeMs,
  });

  final String code;
  final String name;

  /// 最新点位。
  final double price;

  /// 今开。
  final double open;

  /// 最高 / 最低。
  final double high, low;

  /// 昨收。
  final double preClose;

  /// 涨跌额 / 涨跌幅 %。
  final double change, pct;

  /// 振幅 %。
  final double amplitude;

  /// 成交量（A 股指数单位为手，港股为股）。
  final double volume;

  /// 成交额（元 / 港元）。
  final double amount;

  /// 量比；无数据为 0。
  final double volumeRatio;

  /// 换手率 %；港股指数无此字段（0）。
  final double turnoverRate;

  /// 成分股总市值 / 流通市值（元）；港股指数无此字段（0）。
  final double totalMv, floatMv;

  /// 52 周最高 / 最低点位。
  final double high52w, low52w;

  /// 行情时间戳（秒）。
  final int quoteTimeMs;
}

/// 指数日 K 一根（不复权）。
class IndexKline {
  const IndexKline({
    required this.date,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  final String date; // yyyy-MM-dd
  final double open, close, high, low;

  /// 成交量（手 / 股）。
  final double volume;

  /// 成交额（元 / 港元）。
  final double amount;
}
