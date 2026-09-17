import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:funds_valuation/models.dart';
import 'package:funds_valuation/services/estimator.dart';
import 'package:funds_valuation/services/fund_api.dart';
import 'package:funds_valuation/services/index_info.dart';
import 'package:funds_valuation/services/market_api.dart';
import 'package:funds_valuation/state.dart';

void main() {
  group('Estimator', () {
    test('按持仓权重加权计算估值', () {
      final holdings = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 10, market: '1', industry: '食品饮料'),
        FundHolding(code: '00700', name: '腾讯控股', weight: 5, market: '116', industry: '传媒'),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
        '116.00700': const Quote(price: 400, pct: -1, change: -4),
      };
      // (10*2 + 5*-1) / 15 = 1.0；仓位 80% → 0.8
      final pct = Estimator.compute(holdings, quotes, 80);
      expect(pct, closeTo(0.8, 1e-9));
    });

    test('无持仓返回 null', () {
      expect(Estimator.compute([], const {}, 90), isNull);
    });

    test('行情缺失时从分母剔除', () {
      final holdings = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 10, market: '1', industry: ''),
        FundHolding(code: 'AAPL', name: '苹果', weight: 10, market: '105', industry: ''),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 3, change: 3),
      };
      final pct = Estimator.compute(holdings, quotes, 100);
      expect(pct, closeTo(3, 1e-9));
    });

    test('混合估值：重仓实时 + 剩余板块拟合 + 现金', () {
      final hs = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 30, market: '1', industry: '白酒'),
        FundHolding(code: '601318', name: '中国平安', weight: 20, market: '1', industry: '保险'),
      ];
      final quotes = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
        '1.601318': const Quote(price: 50, pct: 4, change: 2),
      };
      // 仓位 80：重仓 50 → (30×2+20×4)/100 = 1.4；剩余 30×板块 1% = 0.3；现金 0。
      expect(Estimator.computeHybrid(hs, quotes, 80, 1.0), closeTo(1.7, 1e-9));
      // 无仓位披露：退化为重仓归一化 (30×2+20×4)/50 = 2.8。
      expect(Estimator.computeHybrid(hs, quotes, 0, 1.0), closeTo(2.8, 1e-9));
      // 板块数据未就绪：剩余部分贡献 0。
      expect(
          Estimator.computeHybrid(hs, quotes, 80, double.nan),
          closeTo(1.4, 1e-9));
      // 重仓权重超出仓位：剩余部分为 0。
      expect(Estimator.computeHybrid(hs, quotes, 40, 5.0), closeTo(1.4, 1e-9));
      // V2 现金剥离：仓位 50（现金 50 不参与），重仓 40 → (40×2+10×4)/100 = 1.2。
      final hs2 = [
        FundHolding(code: '600519', name: '贵州茅台', weight: 40, market: '1', industry: '白酒'),
      ];
      final quotes2 = {
        '1.600519': const Quote(price: 100, pct: 2, change: 2),
      };
      expect(Estimator.computeHybrid(hs2, quotes2, 50, 4.0), closeTo(1.2, 1e-9));
    });

    test('estNav 推算', () {
      expect(Estimator.estNav(1.0, 2.5), closeTo(1.025, 1e-9));
    });
  });

  group('FundQuote', () {
    test('NaN 表示无估值', () {
      final q = FundQuote(code: '000001', nav: 1.5);
      expect(q.hasEst, isFalse);
      q.estPct = 1.23;
      expect(q.hasEst, isTrue);
      expect(q.estNav, 0);
    });
  });

  group('Estimator.aggregateTrend', () {
    test('并集时间轴 + 前向填充 + 加权', () {
      final pts = Estimator.aggregateTrend([
        (
          weight: 10,
          series: {'09:30': 1.0, '09:31': 2.0, '09:32': 4.0}
        ),
        (weight: 10, series: {'09:30': 3.0}),
      ]);
      expect(pts.map((p) => p.label), ['09:30', '09:31', '09:32']);
      expect(pts[0].value, closeTo(2.0, 1e-9)); // (1+3)/2
      expect(pts[1].value, closeTo(2.5, 1e-9)); // (2+3)/2 前向填充
      expect(pts[2].value, closeTo(3.5, 1e-9)); // (4+3)/2
    });

    test('仓位因子', () {
      final pts = Estimator.aggregateTrend(
        [(weight: 1, series: {'09:30': 5.0})],
        factor: 0.8,
      );
      expect(pts.single.value, closeTo(4.0, 1e-9));
    });

    test('空输入返回空', () {
      expect(Estimator.aggregateTrend(const []), isEmpty);
    });
  });

  group('FundApi.parseRank', () {
    test('解析排行数据行', () {
      const body = 'var rankData = {datas:['
          '"001040,新华策略精选股票A,XHCLJXGPA,2026-09-16,3.9623,4.4003,6.99,7.57,'
          '10.48,-1.8,43.56,85.28,364.62,211.99,77.01,395.32,2015-03-31,1,244.4580,1.50%,0.15%,1,0.15%,1,115.04",'
          '"027611,富国中证工程机械主题ETF发起式联接C,FGZZGCJXZTETFFQSLJC,2026-09-16,'
          '0.9506,0.9506,-2.71,-6.58,-7.07,,,,,,,-4.94,2026-07-07,1,-4.94,,0.00%,,,,"],'
          'allRecords:20356,allNum:20356};';
      final items = FundApi.parseRankItems(FundApi.parseRankBody(body));
      expect(items.length, 2);
      expect(items[0].code, '001040');
      expect(items[0].name, '新华策略精选股票A');
      expect(items[0].pct, closeTo(6.99, 1e-9));
      expect(items[0].navDate, '2026-09-16');
      expect(items[1].pct, closeTo(-2.71, 1e-9));
    });

    test('空数据与无涨幅行被跳过', () {
      final items = FundApi.parseRankItems(FundApi.parseRankBody(
          'var rankData = {datas:["001040,某基金,XXX,2026-09-16,1,1,,,"]};'));
      expect(items, isEmpty);
      expect(FundApi.parseRankItems(FundApi.parseRankBody('bad')), isEmpty);
    });

    test('全市场涨跌分布聚合', () {
      const body = 'var rankData = {datas:['
          '"001,A,X,2026-09-16,1,1,2.5",'
          '"002,B,X,2026-09-16,1,1,-1.0",'
          '"003,C,X,2026-09-16,1,1,0.0",'
          '"004,D,X,2026-09-16,1,1,0.5"],allRecords:4};';
      final s = FundApi.parseRankStats(FundApi.parseRankBody(body) ?? const []);
      expect(s.total, 4);
      expect(s.up, 2);
      expect(s.down, 1);
      expect(s.flat, 1);
      expect(s.avg, closeTo((2.5 - 1.0 + 0.0 + 0.5) / 4, 1e-9));
      expect(s.median, closeTo(0.25, 1e-9));
    });
  });

  group('HoldingDist 市场/行业分布', () {
    FundHolding h(String code, String market, String ind, double w) =>
        FundHolding(code: code, name: code, weight: w, market: market, industry: ind);

    test('板块判定：沪/深/科创/创业/北/港/海外', () {
      expect(HoldingDist.boardOf('600519', '1'), '上交所主板');
      expect(HoldingDist.boardOf('601318', '1'), '上交所主板');
      expect(HoldingDist.boardOf('688256', '1'), '上交所科创板');
      expect(HoldingDist.boardOf('689009', '1'), '上交所科创板');
      expect(HoldingDist.boardOf('000568', '0'), '深交所主板');
      expect(HoldingDist.boardOf('002384', '0'), '深交所主板');
      expect(HoldingDist.boardOf('300308', '0'), '深交所创业板');
      expect(HoldingDist.boardOf('301308', '0'), '深交所创业板');
      expect(HoldingDist.boardOf('835174', '0'), '北交所主板');
      expect(HoldingDist.boardOf('430047', '0'), '北交所主板');
      expect(HoldingDist.boardOf('920819', '0'), '北交所主板');
      expect(HoldingDist.boardOf('00700', '116'), '港股');
      expect(HoldingDist.boardOf('09988', ''), '港股'); // 5 位数字即港股
      expect(HoldingDist.boardOf('AAPL', '105'), '其他市场');
      // 未识别代码按市场号兜底。
      expect(HoldingDist.boardOf('609999', '1'), '上交所主板');
    });

    test('交易所聚合：板块归入对应交易所', () {
      expect(HoldingDist.exchangeOf('688256', '1'), '上交所');
      expect(HoldingDist.exchangeOf('300308', '0'), '深交所');
      expect(HoldingDist.exchangeOf('835174', '0'), '北交所');
      expect(HoldingDist.exchangeOf('00700', '116'), '港交所');
      expect(HoldingDist.exchangeOf('AAPL', '105'), '其他市场');

      final hs = [
        h('600519', '1', '食品饮料', 10),
        h('688256', '1', '电子', 6),
        h('002384', '0', '电子', 4),
        h('300308', '0', '通信', 8),
        h('835174', '0', '机械', 2),
        h('00700', '116', '传媒', 5),
        h('AAPL', '105', '电子', 3),
      ];
      final ex = Map.fromEntries(
          HoldingDist.byExchange(hs).map((e) => MapEntry(e.$1, e.$2)));
      expect(ex['上交所'], closeTo(16, 1e-9));
      expect(ex['深交所'], closeTo(12, 1e-9));
      expect(ex['北交所'], closeTo(2, 1e-9));
      expect(ex['港交所'], closeTo(5, 1e-9));
      expect(ex['其他市场'], closeTo(3, 1e-9));
      // 顺序遵循 exchangeOrder。
      expect(HoldingDist.byExchange(hs).map((e) => e.$1).toList(),
          ['上交所', '深交所', '北交所', '港交所', '其他市场']);
    });

    test('板块聚合顺序遵循 boardOrder', () {
      final hs = [
        h('300308', '0', '通信', 8),
        h('00700', '116', '传媒', 5),
        h('600519', '1', '食品饮料', 10),
      ];
      final boards = HoldingDist.byBoard(hs);
      expect(boards.map((e) => e.$1).toList(),
          ['上交所主板', '深交所创业板', '港股']);
      expect(boards.map((e) => e.$2).toList(), [10, 8, 5]);
    });

    test('行业聚合：降序、小行业并入其他行业、空行业兜底', () {
      final hs = [
        h('600519', '1', '食品饮料', 10),
        h('000858', '0', '食品饮料', 4),
        h('000568', '0', '食品饮料', 2),
        h('300308', '0', '通信', 9),
        h('688256', '1', '电子', 3),
        h('002384', '0', '电子', 2),
        h('00700', '116', '传媒', 1),
        h('601318', '1', '银行', 1.5),
        h('600036', '1', '医药生物', 0.8),
        h('AAPL', '105', '', 0.2),
      ];
      final ind = HoldingDist.byIndustry(hs, top: 3);
      expect(ind.first.$1, '食品饮料');
      expect(ind.first.$2, closeTo(16, 1e-9));
      expect(ind[1].$1, '通信');
      // 前三：食品饮料16、通信9、电子5；第 4 名起合并：
      // 传媒1 + 银行1.5 + 医药0.8 + 空行业0.2 = 3.5。
      expect(ind.last.$1, '其他行业');
      expect(ind.last.$2, closeTo(3.5, 1e-9));
      expect(ind.length, 4);
    });

    test('withRemainder 补齐未披露/非股票资产，超配不追加', () {
      final r = HoldingDist.withRemainder([('港股', 30), ('上交所', 20)]);
      expect(r.last.$1, '其他未披露');
      expect(r.last.$2, closeTo(50, 1e-9));
      // 合计已达 100（或四舍五入误差内）不追加。
      final none =
          HoldingDist.withRemainder([('港股', 60), ('上交所', 40.01)]);
      expect(none.length, 2);
    });
  });

  group('自选备份导入导出', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final app = AppState.shared;
      app.funds
        ..clear()
        ..addAll([
          FundItem(code: '000001', name: '华夏成长', type: '混合型',
              amount: 1000, costAmount: 900, group: '支付宝'),
          FundItem(code: '000002', name: '南方稳健', amount: 2000),
        ]);
      app.trades
        ..clear()
        ..add(TradeRecord(code: '000001', time: 1000, buy: true, amount: 1000));
    });

    test('导出结构完整且覆盖导入可往返', () async {
      final app = AppState.shared;
      final raw = app.exportFundsJson();
      final m = jsonDecode(raw) as Map<String, dynamic>;
      expect(m['app'], 'funds-valuation');
      expect(m['format'], 1);
      expect(m['fundCount'], 2);
      expect((m['funds'] as List).length, 2);
      expect((m['trades'] as List).length, 1);
      expect(m['exportedAt'], isNotEmpty);

      // 清空后覆盖导入，数据应完整还原。
      app.funds.clear();
      app.trades.clear();
      final r = await app.importFundsJson(raw, replace: true);
      expect(r.replaced, isTrue);
      expect(r.total, 2);
      expect(app.funds.length, 2);
      expect(app.funds.first.code, '000001');
      expect(app.funds.first.group, '支付宝');
      expect(app.funds.first.costAmount, 900);
      expect(app.trades.length, 1);
      expect(app.trades.first.amount, 1000);
    });

    test('合并导入：保留已有、更新同码、追加新码', () async {
      final app = AppState.shared;
      final backup = jsonEncode({
        'app': 'funds-valuation',
        'format': 1,
        'funds': [
          {'code': '000002', 'name': '南方稳健改名', 'type': '', 'amount': 5000},
          {'code': '000003', 'name': '新增基金', 'type': '指数型'},
        ],
        'trades': [
          {'code': '000003', 'time': 2000, 'buy': true, 'amount': 3000},
          {'code': '000001', 'time': 1000, 'buy': true, 'amount': 1000}, // 重复
        ],
      });
      final r = await app.importFundsJson(backup, replace: false);
      expect(r.added, 1);
      expect(r.updated, 1);
      expect(app.funds.length, 3);
      final b = app.funds.firstWhere((f) => f.code == '000002');
      expect(b.name, '南方稳健改名');
      expect(b.amount, 5000);
      expect(app.funds.any((f) => f.code == '000001'), isTrue);
      // 交易记录去重：仅新增 1 条。
      expect(app.trades.length, 2);
    });

    test('覆盖导入会清除原有自选', () async {
      final app = AppState.shared;
      final backup = jsonEncode({
        'funds': [
          {'code': '000009', 'name': '全新基金'}
        ],
      });
      final r = await app.importFundsJson(backup, replace: true);
      expect(r.added, 1);
      expect(app.funds.length, 1);
      expect(app.funds.single.code, '000009');
      expect(app.trades, isEmpty);
    });

    test('兼容顶层为基金数组的简单格式', () async {
      final app = AppState.shared;
      final backup = jsonEncode([
        {'code': '000010', 'name': '数组基金'}
      ]);
      final r = await app.importFundsJson(backup, replace: true);
      expect(r.total, 1);
      expect(app.funds.single.code, '000010');
    });

    test('非法内容抛出 FormatException', () async {
      final app = AppState.shared;
      await expectLater(
          () => app.importFundsJson('not json', replace: true),
          throwsA(isA<FormatException>()));
      await expectLater(
          () => app.importFundsJson(jsonEncode({'foo': 1}), replace: true),
          throwsA(isA<FormatException>()));
      await expectLater(
          () => app.importFundsJson(jsonEncode({'funds': []}), replace: true),
          throwsA(isA<FormatException>()));
    });

    test('无效条目跳过并计数', () async {
      final app = AppState.shared;
      final backup = jsonEncode({
        'funds': [
          {'code': '', 'name': '无代码'},
          'bad-item',
          {'code': '000020', 'name': '有效基金'},
        ],
      });
      final r = await app.importFundsJson(backup, replace: true);
      expect(r.total, 1);
      expect(r.invalid, 2);
      expect(app.funds.single.code, '000020');
    });
  });

  group('指数档案库', () {
    test('排行榜全部指数均有详细档案', () {
      for (final m in [
        ...MarketApi.indexRankA,
        ...MarketApi.indexRankHK,
      ]) {
        final info = IndexInfoLib.of(m.$1, m.$3);
        expect(info.fullName.trim(), isNotEmpty, reason: '${m.$2} 全称为空');
        expect(info.publisher.trim(), isNotEmpty, reason: '${m.$2} 机构为空');
        expect(info.constituents.trim(), isNotEmpty, reason: '${m.$2} 样本为空');
        expect(info.baseInfo.trim(), isNotEmpty, reason: '${m.$2} 基日为空');
        // 介绍应足够详细（>= 60 字）。
        expect(info.summary.length, greaterThanOrEqualTo(60),
            reason: '${m.$2} 介绍过短: ${info.summary.length}字');
        expect(info.tags, isNotEmpty, reason: '${m.$2} 无标签');
      }
    });

    test('全球指数均有详细档案', () {
      for (final (secid, name) in MarketApi.globalIndices) {
        final info = IndexInfoLib.of(secid, '全球');
        expect(info.fullName.trim(), isNotEmpty,
            reason: '$name 全称为空');
        expect(info.publisher.trim(), isNotEmpty,
            reason: '$name 机构为空');
        expect(info.constituents.trim(), isNotEmpty,
            reason: '$name 样本为空');
        expect(info.baseInfo.trim(), isNotEmpty,
            reason: '$name 基日为空');
        expect(info.summary.length, greaterThanOrEqualTo(60),
            reason: '$name 介绍过短: ${info.summary.length}字');
        expect(info.tags, isNotEmpty, reason: '$name 无标签');
      }
    });

    test('未知 secid 返回按分组兜底档案', () {
      final a = IndexInfoLib.of('1.999999', '宽基');
      expect(a.summary, isNotEmpty);
      final hk = IndexInfoLib.of('100.UNKNOWN', '港股');
      expect(hk.tags, contains('港股'));
      final g = IndexInfoLib.of('100.UNKNOWN', '全球');
      expect(g.tags, contains('全球'));
    });
  });

  group('指数排行清单', () {
    test('secid 无重复且分组合法', () {
      for (final list in [MarketApi.indexRankA, MarketApi.indexRankHK]) {
        final ids = list.map((e) => e.$1).toList();
        expect(ids.toSet().length, ids.length, reason: 'secid 重复: $ids');
        expect(list.every((e) => e.$2.isNotEmpty), isTrue);
      }
      for (final e in MarketApi.indexRankA) {
        expect(['宽基', '风格', '行业'].contains(e.$3), isTrue,
            reason: '${e.$2} 分组非法: ${e.$3}');
      }
      expect(MarketApi.indexRankHK.every((e) => e.$3 == '港股'), isTrue);
    });

    test('主流宽基与行业覆盖完整', () {
      final names = MarketApi.indexRankA.map((e) => e.$2).toList();
      for (final n in [
        '上证指数', '深证成指', '创业板指', '科创50', '沪深300',
        '中证500', '中证1000', '北证50', '中证A500',
        '中证银行', '证券公司', '中证白酒', '中证医疗', '中证半导',
      ]) {
        expect(names, contains(n), reason: '缺少主流指数: $n');
      }
      expect(MarketApi.indexRankHK.length, greaterThanOrEqualTo(16));
    });
  });

  group('FundItem 持久化', () {
    test('amount/costAmount/group 字段往返', () {
      final f = FundItem(
          code: '005827',
          name: '易方达蓝筹精选混合',
          amount: 5000.5,
          costAmount: 4800,
          group: '支付宝');
      final back = FundItem.fromJson(f.toJson());
      expect(back.group, '支付宝');
      expect(back.amount, closeTo(5000.5, 1e-9));
      expect(back.costAmount, closeTo(4800, 1e-9));
    });

    test('旧数据份额+成本自动换算为金额', () {
      final back = FundItem.fromJson({
        'code': '005827',
        'name': '易方达蓝筹精选混合',
        'shares': 1200.55,
        'cost': 1.532,
      });
      expect(back.amount, closeTo(1200.55 * 1.532, 1e-6));
      expect(back.costAmount, closeTo(1200.55 * 1.532, 1e-6));
      expect(back.group, '');
    });

    test('旧数据无 group 字段兼容', () {
      final back =
          FundItem.fromJson({'code': '005827', 'name': '易方达蓝筹精选混合'});
      expect(back.group, '');
      expect(back.amount, 0);
      expect(back.costAmount, 0);
    });
  });
}
