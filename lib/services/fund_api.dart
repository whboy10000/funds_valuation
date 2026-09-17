import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models.dart';
import 'http_client.dart';
import 'market_api.dart';

/// 天天基金 / 东财基金接口封装。
///
/// 说明：官方盘中估值接口已下线（fundgz 404、FundMNFInfo 的 GSZ 恒为 null），
/// 本应用的实时估值由重仓股行情自算，见 [Estimator]。
class FundApi {
  static const _mobBase =
      'https://fundmobapi.eastmoney.com/FundMNewApi';
  static const _mobQuery =
      'plat=Android&appType=ttjj&product=EFund&Version=1&deviceid=fundvaluation';

  /// 搜索基金（代码/名称/拼音）。
  static Future<List<FundSearchHit>> search(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final url = 'https://fundsuggest.eastmoney.com/FundSearch/api/'
        'FundSearchAPI.ashx?m=1&key=${Uri.encodeComponent(keyword.trim())}'
        '&pageindex=0&pagesize=20&callback=__fundSearchCb';
    dynamic data;
    if (kIsWeb) {
      // fundsuggest 无 CORS 头，走 JSONP。
      data = await jsonpFetch(url, '__fundSearchCb');
    } else {
      data = stripJsonp(await httpGet(url));
    }
    final list = (data?['Datas'] as List?) ?? const [];
    final hits = <FundSearchHit>[];
    for (final d in list) {
      final base = d['FundBaseInfo'];
      if (base == null) continue; // 跳过股票等非基金结果
      final code = (base['FCODE'] ?? d['CODE'] ?? '') as String;
      final name = (base['SHORTNAME'] ?? d['NAME'] ?? '') as String;
      if (code.isEmpty || name.isEmpty) continue;
      hits.add(FundSearchHit(
        code: code,
        name: name,
        type: (base['FTYPE'] ?? '') as String,
        company: (base['JJGS'] ?? '') as String,
        manager: (base['JJJL'] ?? '') as String,
      ));
    }
    return hits;
  }

  /// 批量获取最新净值信息。
  static Future<Map<String, FundNavInfo>> navInfo(List<String> codes) async {
    if (codes.isEmpty) return {};
    final url =
        '$_mobBase/FundMNFInfo?$_mobQuery&Fcodes=${codes.join(',')}';
    final data = await httpGetJson(url, referer: 'https://fund.eastmoney.com/');
    final out = <String, FundNavInfo>{};
    for (final d in (data?['Datas'] as List?) ?? const []) {
      final code = (d['FCODE'] ?? '') as String;
      if (code.isEmpty) continue;
      out[code] = FundNavInfo(
        code: code,
        name: (d['SHORTNAME'] ?? '') as String,
        nav: double.tryParse('${d['NAV']}') ?? 0,
        accNav: double.tryParse('${d['ACCNAV']}') ?? 0,
        navDate: (d['PDATE'] ?? '') as String,
        navPct: double.tryParse('${d['NAVCHGRT']}') ?? 0,
      );
    }
    return out;
  }

  /// 获取基金前十大重仓股（含债券/FOF 持仓时仅取股票部分）。
  static Future<List<FundHolding>> holdings(String code) async {
    final url = '$_mobBase/FundMNInverstPosition?$_mobQuery&FCODE=$code';
    final data = await httpGetJson(url);
    final stocks = (data?['Datas']?['fundStocks'] as List?) ?? const [];
    final out = <FundHolding>[];
    for (final s in stocks) {
      final code2 = (s['GPDM'] ?? '') as String;
      final name = (s['GPJC'] ?? '') as String;
      if (code2.isEmpty) continue;
      out.add(FundHolding(
        code: code2,
        name: name,
        weight: double.tryParse('${s['JZBL']}') ?? 0,
        market: (s['NEWTEXCH'] ?? '0') as String,
        industry: (s['INDEXNAME'] ?? '') as String,
      ));
    }
    return out;
  }

  /// 解析 pingzhongdata 详情（历史净值、经理、仓位、阶段收益、概况）。
  static Future<FundDetail?> detail(String code) async {
    final url = 'https://fund.eastmoney.com/pingzhongdata/$code.js';
    Map<String, dynamic> vars;
    if (kIsWeb) {
      vars = (await loadJsVars(url, [
        'fS_name',
        'Data_currentFundManager',
        'Data_netWorthTrend',
        'Data_fundSharesPositions',
        'syl_1y',
        'syl_3y',
        'syl_6y',
        'syl_1n',
        'fund_Rate',
        'fund_sourceRate',
        'fund_minsg',
        'Data_performanceEvaluation',
        'Data_holderStructure',
        'Data_fluctuationScale',
        'Data_IndustriesAllocation',
        'Data_buySecurities',
        'Data_assetAllocation',
        'Data_buySedemption',
        'Data_rateInSimilarType',
        'Data_rateInSimilarPersent',
      ]))!;
    } else {
      final text = await httpGet(url);
      vars = {
        'fS_name': _scalarVar(text, 'fS_name'),
        'Data_currentFundManager': _jsonVar(text, 'Data_currentFundManager'),
        'Data_netWorthTrend': _jsonVar(text, 'Data_netWorthTrend'),
        'Data_fundSharesPositions': _jsonVar(text, 'Data_fundSharesPositions'),
        'syl_1y': _scalarVar(text, 'syl_1y'),
        'syl_3y': _scalarVar(text, 'syl_3y'),
        'syl_6y': _scalarVar(text, 'syl_6y'),
        'syl_1n': _scalarVar(text, 'syl_1n'),
        'fund_Rate': _scalarVar(text, 'fund_Rate'),
        'fund_sourceRate': _scalarVar(text, 'fund_sourceRate'),
        'fund_minsg': _scalarVar(text, 'fund_minsg'),
        'Data_performanceEvaluation':
            _jsonVar(text, 'Data_performanceEvaluation'),
        'Data_holderStructure': _jsonVar(text, 'Data_holderStructure'),
        'Data_fluctuationScale': _jsonVar(text, 'Data_fluctuationScale'),
        'Data_IndustriesAllocation':
            _jsonVar(text, 'Data_IndustriesAllocation'),
        'Data_buySecurities': _jsonVar(text, 'Data_buySecurities'),
        'Data_assetAllocation': _jsonVar(text, 'Data_assetAllocation'),
        'Data_buySedemption': _jsonVar(text, 'Data_buySedemption'),
        'Data_rateInSimilarType': _jsonVar(text, 'Data_rateInSimilarType'),
        'Data_rateInSimilarPersent':
            _jsonVar(text, 'Data_rateInSimilarPersent'),
      };
    }
    final name = '${vars['fS_name']}';
    if (name.isEmpty || name == 'null') return null;
    final managers = (vars['Data_currentFundManager'] as List?) ?? const [];
    final mgr = managers.isNotEmpty ? managers.first : null;
    final positions = (vars['Data_fundSharesPositions'] as List?) ?? const [];
    double pos = 0;
    var reportDate = '';
    if (positions.isNotEmpty && positions.last is List) {
      final last = positions.last as List;
      if (last.length >= 2) {
        pos = _toDouble(last.last);
        // 末项 [报告期时间戳(ms), 股票仓位]，与重仓股同一季报披露周期。
        reportDate = _fmtReportTs(last.first);
      }
    }
    final trendRaw = (vars['Data_netWorthTrend'] as List?) ?? const [];
    final trend = <List<double>>[];
    for (final e in trendRaw) {
      if (e is Map) {
        final x = _toDouble(e['x']);
        final y = _toDouble(e['y']);
        if (x > 0 && y > 0) trend.add([x, y]);
      }
    }
    // 概况：费率 / 持有人结构 / 规模变动 / 行业配置 / 重仓债券。
    // Data_holderStructure 实为 Map：
    // {series:[{name:机构持有比例,data:[..]},{name:个人持有比例,..}],categories:[..]}。
    final holdersObj = vars['Data_holderStructure'];
    double inst = -1, personal = -1;
    var holderReport = '';
    if (holdersObj is Map) {
      final cats = (holdersObj['categories'] as List?) ?? const [];
      final series = (holdersObj['series'] as List?) ?? const [];
      double lastOf(String name) {
        for (final s in series.whereType<Map>()) {
          if ('${s['name']}'.contains(name)) {
            final d = (s['data'] as List?) ?? const [];
            return d.isEmpty ? -1 : _toDouble(d.last);
          }
        }
        return -1;
      }

      inst = lastOf('机构');
      personal = lastOf('个人');
      if (cats.isNotEmpty) holderReport = _fmtReportTs(cats.last);
    }
    // Data_fluctuationScale 实为 Map：{categories:[..],series:[{name,data:[..]}]}。
    final scaleObj = vars['Data_fluctuationScale'];
    final scales = <(String, double)>[];
    if (scaleObj is Map) {
      final cats = (scaleObj['categories'] as List?) ?? const [];
      final series = (scaleObj['series'] as List?) ?? const [];
      List<double>? data;
      for (final s in series.whereType<Map>()) {
        if (data == null || '${s['name']}'.contains('规模')) {
          data = [
            for (final v in (s['data'] as List?) ?? const []) _toDouble(v)
          ];
        }
      }
      final d = data ?? const <double>[];
      for (var i = 0; i < cats.length; i++) {
        final label = _quarterLabel(cats[i]);
        if (label == null) continue;
        scales.add((label, i < d.length ? d[i] : 0));
      }
    }
    final indRaw = (vars['Data_IndustriesAllocation'] as List?) ?? const [];
    var industries = <(String, double)>[];
    if (indRaw.isNotEmpty && indRaw.last is Map) {
      final e = indRaw.last as Map;
      final names = (e['y'] as List?) ?? const [];
      final vals = (e['sc'] as List?) ?? const [];
      for (var i = 0; i < names.length && i < vals.length; i++) {
        final v = _toDouble(vals[i]);
        if ('${names[i]}'.isNotEmpty && v > 0) {
          industries.add(('${names[i]}', v));
        }
      }
      industries.sort((a, b) => b.$2.compareTo(a.$2));
      if (industries.length > 8) {
        industries = industries.sublist(0, 8);
      }
    }
    // 重仓债券。
    final bondRaw = (vars['Data_buySecurities'] as List?) ?? const [];
    final bonds = <(String, double)>[];
    for (final e in bondRaw.whereType<Map>()) {
      final nm = '${e['s'] ?? ''}';
      if (nm.isEmpty) continue;
      final ys = (e['y'] as List?) ?? const [];
      final v = ys.isEmpty ? 0.0 : _toDouble(ys.last);
      bonds.add((nm, v));
    }
    // 能力评分雷达：{"avr":"64.00","categories":[..],"data":[..]}。
    final radar = <(String, double)>[];
    var radarAvr = '';
    final perfObj = vars['Data_performanceEvaluation'];
    if (perfObj is Map) {
      radarAvr = '${perfObj['avr'] ?? ''}';
      final cats = (perfObj['categories'] as List?) ?? const [];
      final vals = (perfObj['data'] as List?) ?? const [];
      for (var i = 0; i < cats.length && i < vals.length; i++) {
        final v = _toDouble(vals[i]);
        if ('${cats[i]}'.isNotEmpty) radar.add(('${cats[i]}', v));
      }
    }
    // 同类排名：Data_rateInSimilarType [{x,y(排名),sc(总数)}]，
    // Data_rateInSimilarPersent [[ts, 百分位%]]。
    final rankRaw = (vars['Data_rateInSimilarType'] as List?) ?? const [];
    var rankNum = 0, rankTotal = 0;
    if (rankRaw.isNotEmpty && rankRaw.last is Map) {
      final e = rankRaw.last as Map;
      rankNum = _toDouble(e['y']).round();
      rankTotal = _toDouble(e['sc']).round();
    }
    final pctRaw = (vars['Data_rateInSimilarPersent'] as List?) ?? const [];
    var rankPct = -1.0;
    if (pctRaw.isNotEmpty && pctRaw.last is List && (pctRaw.last as List).length >= 2) {
      rankPct = _toDouble((pctRaw.last as List).last);
    }
    // 资产配置趋势：series [股票/债券/现金占净比] + categories。
    final alloc = <(String, double, double, double)>[];
    final allocObj = vars['Data_assetAllocation'];
    if (allocObj is Map) {
      final cats = (allocObj['categories'] as List?) ?? const [];
      final series = (allocObj['series'] as List?) ?? const [];
      List<double> pick(String name) {
        for (final s in series.whereType<Map>()) {
          if ('${s['name']}'.contains(name)) {
            return [for (final v in (s['data'] as List?) ?? const []) _toDouble(v)];
          }
        }
        return const [];
      }
      final stock = pick('股票'), bond = pick('债券'), cash = pick('现金');
      final n = cats.length;
      final from = n > 6 ? n - 6 : 0;
      for (var i = from; i < n; i++) {
        alloc.add((
          '${cats[i]}',
          i < stock.length ? stock[i] : 0,
          i < bond.length ? bond[i] : 0,
          i < cash.length ? cash[i] : 0,
        ));
      }
    }
    // 申赎与份额：series [期间申购/期间赎回/总份额] + categories。
    final buyback = <(String, double, double, double)>[];
    final bbObj = vars['Data_buySedemption'];
    if (bbObj is Map) {
      final cats = (bbObj['categories'] as List?) ?? const [];
      final series = (bbObj['series'] as List?) ?? const [];
      List<double> pick(String name) {
        for (final s in series.whereType<Map>()) {
          if ('${s['name']}'.contains(name)) {
            return [for (final v in (s['data'] as List?) ?? const []) _toDouble(v)];
          }
        }
        return const [];
      }
      final buy = pick('申购'), sell = pick('赎回'), total = pick('份额');
      final n = cats.length;
      final from = n > 6 ? n - 6 : 0;
      for (var i = from; i < n; i++) {
        buyback.add((
          '${cats[i]}',
          i < buy.length ? buy[i] : 0,
          i < sell.length ? sell[i] : 0,
          i < total.length ? total[i] : 0,
        ));
      }
    }
    // 股票仓位历史。
    final posHist = <(String, double)>[];
    for (final e in positions) {
      if (e is List && e.length >= 2) {
        final label = _quarterLabel(e.first);
        if (label != null) posHist.add((label, _toDouble(e.last)));
      }
    }
    // 特色数据（自算，取最近一年日净值）：年化波动率 / 最大回撤 / 夏普。
    var volat = -1.0, maxDrawdown = -1.0, sharpe = double.nan;
    if (trend.length > 30) {
      final oneYear = trend.length > 244 ? trend.sublist(trend.length - 245) : trend;
      final rets = <double>[];
      var peak = oneYear.first[1], dd = 0.0;
      for (var i = 1; i < oneYear.length; i++) {
        final r = oneYear[i][1] / oneYear[i - 1][1] - 1;
        rets.add(r);
        if (oneYear[i][1] > peak) peak = oneYear[i][1];
        final d = 1 - oneYear[i][1] / peak;
        if (d > dd) dd = d;
      }
      if (rets.length > 20) {
        final mean = rets.reduce((a, b) => a + b) / rets.length;
        final vari =
            rets.fold<double>(0, (a, b) => a + (b - mean) * (b - mean)) /
                (rets.length - 1);
        volat = math.sqrt(vari) * math.sqrt(244) * 100;
        maxDrawdown = dd * 100;
        final annual = math.pow(oneYear.last[1] / oneYear.first[1], 244 / rets.length) - 1;
        if (volat > 0) sharpe = (annual * 100 - 2) / volat;
      }
    }
    return FundDetail(
      name: name,
      code: code,
      managerName: mgr == null ? '' : '${mgr['name']}',
      managerWorkTime: mgr == null ? '' : '${mgr['workTime']}',
      managerSize: mgr == null ? '' : '${mgr['fundSize']}',
      managerStar: mgr == null ? 0 : (int.tryParse('${mgr['star']}') ?? 0),
      navTrend: trend,
      positionRatio: pos,
      reportDate: reportDate,
      syl1m: _fmtSyl(vars['syl_1y']),
      syl3m: _fmtSyl(vars['syl_3y']),
      syl6m: _fmtSyl(vars['syl_6y']),
      syl1y: _fmtSyl(vars['syl_1n']),
      rate: _fmtSyl(vars['fund_Rate']),
      sourceRate: _fmtSyl(vars['fund_sourceRate']),
      minsg: _fmtSyl(vars['fund_minsg']),
      holderInst: inst,
      holderPersonal: personal,
      holderReport: holderReport,
      scales: scales.length > 4 ? scales.sublist(scales.length - 4) : scales,
      industries: industries,
      bonds: bonds,
      radar: radar,
      radarAvr: _fmtSyl(radarAvr),
      rankNum: rankNum,
      rankTotal: rankTotal,
      rankPct: rankPct,
      volat: volat,
      maxDrawdown: maxDrawdown,
      sharpe: sharpe,
      alloc: alloc,
      buyback: buyback,
      positions: posHist.reversed.toList(),
    );
  }

  /// 每日规模序列（亿，估算口径）。
  ///
  /// - 场内基金：流通份额(f85) × 每日收盘价；实时规模用总市值(f116)。
  ///   [quote] 为探测到的场内行情（price>0 且 share>0 判定场内）。
  /// - 场外基金：最新披露份额规模([shareYi] 亿份) × 每日单位净值([navs])。
  ///   份额按季度披露，期间申赎未计入，规模每日变化主要反映净值波动。
  static Future<FundDailyScale?> dailyScale({
    String? etfSecid,
    Quote? quote,
    required double shareYi,
    required List<List<double>> navs,
  }) async {
    if (etfSecid != null && quote != null && quote.price > 0) {
      // 场内：日K 收盘 × 份额。
      final shareY = quote.share / 1e8;
      if (shareY <= 0) return null;
      try {
        final kl = await MarketApi.klineDaily(etfSecid);
        if (kl.length > 10) {
          final series = [for (final e in kl) (e.$1, e.$2 * shareY)];
          final latest = quote.totalWorth > 0
              ? quote.totalWorth / 1e8
              : quote.price * shareY;
          final chg = series.length >= 2
              ? latest - series[series.length - 2].$2
              : double.nan;
          return FundDailyScale(
              isEtf: true,
              series: series,
              latest: latest,
              todayChg: chg,
              shareYi: shareY);
        }
      } catch (_) {}
      return null;
    }
    // 场外：最新份额 × 每日净值（最近一年）。
    if (shareYi > 0 && navs.length > 30) {
      final year = navs.length > 250 ? navs.sublist(navs.length - 251) : navs;
      String label(double ms) {
        final d = DateTime.fromMillisecondsSinceEpoch(ms.round());
        String two(int x) => x.toString().padLeft(2, '0');
        return '${d.year}-${two(d.month)}-${two(d.day)}';
      }

      final series = [for (final e in year) (label(e[0]), e[1] * shareYi)];
      final latest = series.last.$2;
      final chg = series.length >= 2 ? latest - series[series.length - 2].$2 : double.nan;
      return FundDailyScale(
          isEtf: false,
          series: series,
          latest: latest,
          todayChg: chg,
          shareYi: shareYi);
    }
    return null;
  }

  /// 基金档案（f10 页面懒加载）：概况补充 + 分红配送 + 经理变动。
  static Future<FundProfile?> profile(String code) async {
    String fullName = '', setupDate = '', assetScale = '',
        shareScale = '', custodian = '', company = '';
    var shareYi = 0.0;
    final dividends = <(String, String, String, String, String)>[];
    final mgrChanges = <(String, String, String, String, String)>[];
    String strip(String s) =>
        s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('\xa0', ' ').trim();

    // 基本信息：基金全称/成立日期/资产规模/份额规模/管理人/托管人。
    try {
      final text = await httpGet(
        'https://fundf10.eastmoney.com/jbgk_$code.html',
        referer: 'https://fundf10.eastmoney.com/',
      );
      final kv = <String, String>{};
      for (final r in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true)
          .allMatches(text)) {
        final tds = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
            .allMatches(r.group(1)!)
            .map((m) => strip(m.group(1)!))
            .toList();
        for (var i = 0; i + 1 < tds.length; i += 2) {
          kv[tds[i].replaceAll('：', '').replaceAll(':', '')] = tds[i + 1];
        }
      }
      String pick(String contain) {
        for (final e in kv.entries) {
          if (e.key.contains(contain)) return e.value;
        }
        return '';
      }

      fullName = pick('基金全称');
      setupDate = pick('成立日期');
      custodian = pick('基金托管人');
      company = pick('基金管理人');
      // 新版页面规模行标签与数值混排（「净资产规模」「204.16亿元（截止至…）份额规模」
      // 「133.6693亿份（截止至…）」），键值配对会丢失，改为全文正则提取。
      final plain = strip(text);
      String after(String key) {
        final i = plain.indexOf(key);
        if (i < 0) return '';
        var seg = plain.substring(math.min(plain.length, i + key.length));
        if (seg.length > 60) seg = seg.substring(0, 60);
        final j = seg.indexOf('）');
        if (j >= 0) seg = seg.substring(0, j + 1);
        return seg.trim();
      }

      assetScale = after('净资产规模');
      if (assetScale.isEmpty) assetScale = pick('资产规模');
      shareScale = after('份额规模');
      final m = RegExp(r'([\d.]+)\s*亿份').firstMatch(shareScale);
      if (m != null) shareYi = double.tryParse(m.group(1)!) ?? 0;
    } catch (_) {}

    // 分红送配：[年份, 权益登记日, 除息日, 每10份分红, 分红发放日]。
    try {
      final text = await httpGet(
        'https://fundf10.eastmoney.com/fhsp_$code.html',
        referer: 'https://fundf10.eastmoney.com/',
      );
      for (final r in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true)
          .allMatches(text)) {
        final tds = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
            .allMatches(r.group(1)!)
            .map((m) => strip(m.group(1)!))
            .toList();
        if (tds.length < 5) continue;
        if (tds[0].contains('暂无') || tds[2].isEmpty) continue;
        dividends.add((tds[0], tds[1], tds[2], tds[3], tds[4]));
        if (dividends.length >= 10) break;
      }
    } catch (_) {}

    // 经理变动：[起始期, 截止期, 基金经理, 任职期间, 任职回报]。
    try {
      final text = await httpGet(
        'https://fundf10.eastmoney.com/jjjl_$code.html',
        referer: 'https://fundf10.eastmoney.com/',
      );
      for (final r in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true)
          .allMatches(text)) {
        final tds = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
            .allMatches(r.group(1)!)
            .map((m) => strip(m.group(1)!))
            .toList();
        if (tds.length < 5) continue;
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tds[0])) continue;
        mgrChanges.add((tds[0], tds[1], tds[2], tds[3], tds[4]));
        if (mgrChanges.length >= 8) break;
      }
    } catch (_) {}

    if (fullName.isEmpty &&
        dividends.isEmpty &&
        mgrChanges.isEmpty) {
      return null;
    }
    return FundProfile(
      fullName: fullName,
      setupDate: setupDate,
      assetScale: assetScale,
      shareScale: shareScale,
      custodian: custodian,
      company: company,
      shareYi: shareYi,
      dividends: dividends,
      mgrChanges: mgrChanges,
    );
  }

  /// 报告期毫秒时间戳 → 2026Q2 形式的季度标签。
  static String? _quarterLabel(dynamic v) {
    final ms = double.tryParse('$v') ?? 0;
    if (ms <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms.round());
    return '${d.year}Q${(d.month + 2) ~/ 3}';
  }

  /// f10 历史季度重仓股（近两年，新→旧）：(季度标签, {股票代码: 占净值比例})。
  ///
  /// 用于计算十大重仓「较上期变化」（新进/增加/减少/持平）。
  static Future<List<(String, Map<String, double>)>> holdingsHistory(
      String code) async {
    final year = DateTime.now().year;
    final out = <(String, Map<String, double>)>[];
    for (final y in [year, year - 1]) {
      try {
        final text = await httpGet(
          'https://fundf10.eastmoney.com/FundArchivesDatas.aspx'
          '?type=jjcc&code=$code&topline=10&year=$y&month=&rt=0.1',
          referer: 'https://fundf10.eastmoney.com/',
        );
        out.addAll(parseJjcc(text));
      } catch (_) {
        // 单年失败忽略。
      }
    }
    return out;
  }

  /// 解析 FundArchivesDatas jjcc 文本（`var apidata={content:"<html>"}`）。
  ///
  /// content 内为若干季度块，每块一个 HTML 表格；这里按
  /// 「xxxx年x季度股票投资明细」标题切块，提取每行的代码与占净值比例。
  static List<(String, Map<String, double>)> parseJjcc(String text) {
    final out = <(String, Map<String, double>)>[];
    final titleRe = RegExp(r'(\d{4})年(\d)季度股票投资明细');
    final matches = titleRe.allMatches(text).toList();
    String strip(String s) =>
        s.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    for (var k = 0; k < matches.length; k++) {
      final m = matches[k];
      final end =
          k + 1 < matches.length ? matches[k + 1].start : text.length;
      final chunk = text.substring(m.end, end);
      final map = <String, double>{};
      for (final r in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true)
          .allMatches(chunk)) {
        final tds = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
            .allMatches(r.group(1)!)
            .toList();
        if (tds.length < 4) continue;
        final code2 = strip(tds[1].group(1)!);
        if (code2.isEmpty || !RegExp(r'^\d{5,6}$').hasMatch(code2)) continue;
        // 占净值比例：行内第一个以 % 结尾的单元格。
        double? ratio;
        for (final td in tds) {
          final s = strip(td.group(1)!);
          if (s.endsWith('%')) {
            ratio = double.tryParse(s.substring(0, s.length - 1));
            break;
          }
        }
        map[code2] = ratio ?? 0;
      }
      if (map.isNotEmpty) {
        out.add(('${m.group(1)}Q${m.group(2)}', map));
      }
    }
    return out;
  }

  /// 报告期（毫秒时间戳或 yyyy-MM-dd 字符串）→ yyyy/MM/dd。
  static String _fmtReportTs(dynamic v) {
    final s = '$v'.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}/${m.group(2)}/${m.group(3)}';
    final ms = double.tryParse(s) ?? 0;
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms.round());
    String two(int x) => x.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  /// 全市场基金排行（天天基金排行榜，按最新披露净值日增长率 rzdf）。
  ///
  /// [ft] 类型：all 全部 / gp 股票型 / hh 混合型 / zs 指数型 / zq 债券型 / qdii QDII。
  /// [asc] 为 true 时按日涨幅升序（跌幅榜），否则降序（涨幅榜）。
  static Future<List<FundRankItem>> rank({
    String ft = 'all',
    bool asc = false,
    int page = 1,
    int pageSize = 50,
  }) async {
    final now = DateTime.now();
    final ed = _ymd(now);
    final sd = _ymd(now.subtract(const Duration(days: 400)));
    final url = 'https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=kf'
        '&ft=$ft&rs=&gs=0&sc=rzdf&st=${asc ? 'asc' : 'desc'}'
        '&sd=$sd&ed=$ed&qdii=&tabSubtype=,,,,,,,,'
        '&pi=$page&pn=$pageSize&dx=1';
    dynamic data;
    if (kIsWeb) {
      // 返回 `var rankData = {...}`，脚本注入后读全局变量。
      data = (await loadScriptVar(url, ['rankData']))['rankData']?['datas'];
    } else {
      final text = await httpGet(
        url,
        referer: 'https://fund.eastmoney.com/data/fundranking.html',
      );
      data = parseRankBody(text);
    }
    return parseRankItems(data);
  }

  /// 全市场基金排行原始行缓存（rankhandler 全量约 2 万条，一次拉取多方复用）。
  static List<dynamic>? _rankRowsCache;

  /// 全市场基金排行原始行（仅统计卡用）。
  ///
  /// 全量约 2 万条：单请求 4MB 移动端易超时，拆为 5 页 × 5000 依次拉取。
  static Future<List<dynamic>> rankRows() async {
    final cached = _rankRowsCache;
    if (cached != null) return cached;
    final now = DateTime.now();
    final rows = <dynamic>[];
    for (var page = 1; page <= 5; page++) {
      final url = 'https://fund.eastmoney.com/data/rankhandler.aspx?op=ph&dt=kf'
          '&ft=all&rs=&gs=0&sc=rzdf&st=desc'
          '&sd=${_ymd(now.subtract(const Duration(days: 400)))}&ed=${_ymd(now)}'
          '&qdii=&tabSubtype=,,,,,,,,&pi=$page&pn=5000&dx=1';
      List<dynamic> part;
      if (kIsWeb) {
        part = ((await loadScriptVar(url, ['rankData']))['rankData']
                ?['datas'] as List?) ??
            const [];
      } else {
        final text = await httpGet(
          url,
          referer: 'https://fund.eastmoney.com/data/fundranking.html',
        );
        part = parseRankBody(text) ?? const [];
      }
      rows.addAll(part);
      if (part.length < 5000) break;
      // 翻页节流。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _rankRowsCache = rows;
    return rows;
  }

  /// 全市场基金涨跌分布统计（客户端聚合，行数据复用 [rankRows] 缓存）。
  static Future<FundRankStats> rankStats() async {
    final rows = await rankRows();
    return parseRankStats(rows);
  }

  /// 场外基金排行快速版（移动端友好）：
  /// 涨幅榜 / 跌幅榜各拉头部分页（每页 50 只小响应），
  /// 合并去重并剔除场内代码（[excludeCodes]）。
  /// 避免全量 2.5 万条单请求（约 4MB）在弱网下超时导致一直加载。
  static Future<List<FundRankItem>> rankFast(
      {Set<String> excludeCodes = const {}, int perSide = 250}) async {
    final pages = (perSide / 50).ceil();
    // 涨幅榜/跌幅榜各分页并行拉取，整体耗时 ≈ 最慢单页。
    final parts = await Future.wait([
      for (var page = 1; page <= pages; page++)
        for (final asc in const [false, true])
          rank(asc: asc, page: page, pageSize: 50)
              .catchError((_) => <FundRankItem>[]), // 单页失败跳过。
    ]);
    final seen = <String>{};
    final out = <FundRankItem>[];
    for (final items in parts) {
      for (final it in items) {
        if (excludeCodes.contains(it.code) || !seen.add(it.code)) continue;
        out.add(it);
      }
    }
    return out;
  }

  /// 聚合排行行：上涨/平盘/下跌家数、平均与中位数涨幅。
  static FundRankStats parseRankStats(List<dynamic> rows) {
    final pcts = <double>[];
    for (final r in rows) {
      final parts = '$r'.split(',');
      if (parts.length < 7) continue;
      final pct = double.tryParse(parts[6].trim());
      if (pct != null) pcts.add(pct);
    }
    pcts.sort();
    var sum = 0.0;
    var up = 0, down = 0;
    for (final p in pcts) {
      sum += p;
      if (p > 0) up++;
      if (p < 0) down++;
    }
    final median = pcts.isEmpty
        ? 0.0
        : (pcts.length.isOdd
            ? pcts[pcts.length ~/ 2]
            : (pcts[pcts.length ~/ 2 - 1] + pcts[pcts.length ~/ 2]) / 2);
    return FundRankStats(
      total: rows.length,
      up: up,
      flat: rows.length - up - down,
      down: down,
      avg: pcts.isEmpty ? 0 : sum / pcts.length,
      median: median,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 解析 rankhandler 返回文本，提取 datas 行数组。
  ///
  /// 注意：返回的是 `{datas:[...],allRecords:...}` 这样的 JS 对象字面量
  /// （键名无引号），整体不是合法 JSON；这里用括号匹配直接提取
  /// `datas:[...]` 数组（元素均为带引号字符串，可安全 jsonDecode）。
  static List<dynamic>? parseRankBody(String text) {
    final i = text.indexOf('datas:');
    if (i < 0) return null;
    final from = text.indexOf('[', i);
    if (from < 0) return null;
    var depth = 0, inStr = false, esc = false;
    for (var j = from; j < text.length; j++) {
      final c = text.codeUnitAt(j);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5C) {
          esc = true;
        } else if (c == 0x22) {
          inStr = false;
        }
        continue;
      }
      if (c == 0x22) {
        inStr = true;
      } else if (c == 0x5B) {
        depth++;
      } else if (c == 0x5D) {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(text.substring(from, j + 1)) as List;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 解析排行 datas 行：
  /// `code,名称,拼音,净值日期,单位净值,累计净值,日增长率,近1周,...`。
  static List<FundRankItem> parseRankItems(List<dynamic>? rows) {
    final out = <FundRankItem>[];
    for (final r in rows ?? const []) {
      final parts = '$r'.split(',');
      if (parts.length < 7) continue;
      final code = parts[0].trim();
      final name = parts[1].trim();
      if (code.isEmpty || name.isEmpty) continue;
      final pct = double.tryParse(parts[6].trim());
      if (pct == null) continue; // 无日涨幅数据（如未披露净值）。
      out.add(FundRankItem(
        code: code,
        name: name,
        navDate: parts[3].trim(),
        nav: double.tryParse(parts[4].trim()) ?? 0,
        pct: pct,
      ));
    }
    return out;
  }

  static String _fmtSyl(Object? v) {
    final s = '$v';
    if (s.isEmpty || s == 'null' || s == '--') return '--';
    return s;
  }

  static double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  /// 提取 `var name = "..."` / 数字 标量。
  static Object? _scalarVar(String text, String name) {
    final m = RegExp('var\\s+$name\\s*=\\s*("([^"]*)"|[0-9.\\-]+)\\s*;')
        .firstMatch(text);
    if (m == null) return null;
    if (m.group(2) != null) return m.group(2);
    return m.group(1);
  }

  /// 提取 `var name = {...}` / `[...]` JSON。
  static Object? _jsonVar(String text, String name) {
    final key = 'var $name =';
    final start = text.indexOf(key);
    if (start < 0) return null;
    final from = text.indexOf(RegExp('[\\[{]'), start);
    if (from < 0) return null;
    final open = text[from];
    final close = open == '[' ? ']' : '}';
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = from; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5C) {
          esc = true;
        } else if (c == 0x22) {
          inStr = false;
        }
        continue;
      }
      if (c == 0x22) {
        inStr = true;
      } else if (c == open.codeUnitAt(0)) {
        depth++;
      } else if (c == close.codeUnitAt(0)) {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(text.substring(from, i + 1));
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }
}

/// 重仓股归属市场 / 行业分布聚合（详情页「市场占比」「行业分布」饼图）。
///
/// 权重口径均为占净值比例（%），仅基于最新季报前十大重仓股；
/// 不足 100% 的部分为未披露个股与债券/现金等非股票资产，
/// 展示时由 [withRemainder] 追加「其他未披露」灰色扇区。
class HoldingDist {
  /// 板块标准顺序（决定饼图扇区与图例顺序）。
  static const boardOrder = [
    '上交所主板',
    '上交所科创板',
    '深交所主板',
    '深交所创业板',
    '北交所主板',
    '港股',
    '其他市场',
  ];

  /// 交易所标准顺序。
  static const exchangeOrder = [
    '上交所',
    '深交所',
    '北交所',
    '港交所',
    '其他市场',
  ];

  static const _boardExchange = {
    '上交所主板': '上交所',
    '上交所科创板': '上交所',
    '深交所主板': '深交所',
    '深交所创业板': '深交所',
    '北交所主板': '北交所',
    '港股': '港交所',
    '其他市场': '其他市场',
  };

  /// 按股票代码 + 东财市场号判定所属板块。
  ///
  /// - 60x（不含 688/689）→ 上交所主板；688/689 → 上交所科创板；
  /// - 000/001/002/003 → 深交所主板；300/301 → 深交所创业板；
  /// - 43/83/87/88/920 等 4/8 开头六位代码 → 北交所主板；
  /// - 5 位数字代码或市场号 116 → 港股；
  /// - 市场号 0/1 兜底归入深/沪主板，其余（美股 QDII 等）→ 其他市场。
  static String boardOf(String code, String market) {
    final c = code.trim();
    if (market == '116' ||
        (c.length == 5 && RegExp(r'^\d{5}$').hasMatch(c))) {
      return '港股';
    }
    if (RegExp(r'^\d{6}$').hasMatch(c)) {
      if (c.startsWith('688') || c.startsWith('689')) return '上交所科创板';
      if (c.startsWith('60')) return '上交所主板';
      if (c.startsWith('300') || c.startsWith('301')) return '深交所创业板';
      if (c.startsWith('000') ||
          c.startsWith('001') ||
          c.startsWith('002') ||
          c.startsWith('003')) {
        return '深交所主板';
      }
      if (c.startsWith('43') ||
          c.startsWith('83') ||
          c.startsWith('87') ||
          c.startsWith('88') ||
          c.startsWith('920') ||
          c.startsWith('4') ||
          c.startsWith('8')) {
        return '北交所主板';
      }
    }
    if (market == '1') return '上交所主板';
    if (market == '0') return '深交所主板';
    return '其他市场';
  }

  /// 板块 → 交易所。
  static String exchangeOf(String code, String market) =>
      _boardExchange[boardOf(code, market)] ?? '其他市场';

  /// 按板块聚合，顺序遵循 [boardOrder]。
  static List<(String, double)> byBoard(Iterable<FundHolding> holdings) =>
      _aggregate(holdings, (h) => boardOf(h.code, h.market), boardOrder);

  /// 按交易所聚合，顺序遵循 [exchangeOrder]。
  static List<(String, double)> byExchange(Iterable<FundHolding> holdings) =>
      _aggregate(
          holdings, (h) => exchangeOf(h.code, h.market), exchangeOrder);

  /// 按重仓股所属行业（申万一级）聚合降序；[top] 名之外并入「其他行业」。
  static List<(String, double)> byIndustry(
    Iterable<FundHolding> holdings, {
    int top = 8,
  }) {
    final m = <String, double>{};
    for (final h in holdings) {
      final k = h.industry.trim().isEmpty ? '其他行业' : h.industry.trim();
      m[k] = (m[k] ?? 0) + h.weight;
    }
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <(String, double)>[];
    var rest = 0.0;
    for (var i = 0; i < entries.length; i++) {
      if (i < top) {
        out.add((entries[i].key, entries[i].value));
      } else {
        rest += entries[i].value;
      }
    }
    if (rest > 0) out.add(('其他行业', rest));
    return out;
  }

  /// 追加「其他未披露」扇区：100 − 重仓合计（债券/现金/未披露个股等）。
  static List<(String, double)> withRemainder(
    List<(String, double)> slices, {
    String label = '其他未披露',
  }) {
    final sum = slices.fold<double>(0, (a, b) => a + b.$2);
    final rest = 100 - sum;
    if (rest > 0.05) return [...slices, (label, rest)];
    return slices;
  }

  static List<(String, double)> _aggregate(
    Iterable<FundHolding> holdings,
    String Function(FundHolding) keyOf,
    List<String> order,
  ) {
    final m = <String, double>{};
    for (final h in holdings) {
      final k = keyOf(h);
      m[k] = (m[k] ?? 0) + h.weight;
    }
    return [
      for (final k in order)
        if ((m[k] ?? 0) > 0) (k, m[k]!),
    ];
  }
}
