/// 端到端联网集成测试：验证数据服务在真实接口上可用。
///
/// 运行：`flutter test test/api_live_test.dart`
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:funds_valuation/services/estimator.dart';
import 'package:funds_valuation/services/fund_api.dart';
import 'package:funds_valuation/services/market_api.dart';

void main() {
  setUpAll(() async {
    // 避免密集请求触发东财频控。
    await Future<void>.delayed(const Duration(seconds: 2));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(seconds: 2));
  });

  test('净值信息', () async {
    final navs = await FundApi.navInfo(['005827']);
    expect(navs['005827'], isNotNull);
    expect(navs['005827']!.nav, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('搜索', () async {
    final hits = await FundApi.search('白酒');
    expect(hits, isNotEmpty);
    expect(hits.first.code, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('重仓股 + 估值引擎', () async {
    final hs = await FundApi.holdings('005827');
    expect(hs, isNotEmpty);
    final secids = [for (final h in hs) '${h.market}.${h.code}'];
    final quotes = await MarketApi.quotes(secids);
    expect(quotes, isNotEmpty);
    final pct = Estimator.compute(hs, quotes, 83.4);
    expect(pct, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('基金详情(pingzhongdata)', () async {
    final d = await FundApi.detail('005827');
    expect(d, isNotNull);
    expect(d!.navTrend.length, greaterThan(100));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('指数行情 + 涨跌分布', () async {
    final quotes = await MarketApi.quotes(['1.000001', '0.399001']);
    expect(quotes['1.000001'], isNotNull);
    final b = await MarketApi.breadth();
    expect(b, isNotNull);
    expect(b!.up + b.down + b.flat, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('板块与分时', () async {
    final sectors = await MarketApi.sectors(type: 2);
    expect(sectors, isNotEmpty);
    // 分页拉全量后应包含负值板块（修复只显示正值的 bug）。
    expect(sectors.any((s) => s.pct < 0), isTrue);
    final r = await MarketApi.trend('1.000001');
    expect(r.points.length, greaterThan(10));
    expect(r.preClose, greaterThan(0));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('港股指数', () async {
    final quotes = await MarketApi.quotes([
      '100.HSI',
      '124.HSTECH',
      '100.HSCEI',
      '2.931637',
      '2.931454',
      '2.931250',
    ]);
    expect(quotes, isNotEmpty);
    expect(quotes.containsKey('124.HSTECH'), isTrue);
    // 港股通系列指数（中证市场号 2）。
    expect(quotes.containsKey('2.931637'), isTrue);
    expect(quotes.containsKey('2.931454'), isTrue);
    expect(quotes.containsKey('2.931250'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('板块成分股', () async {
    final members = await MarketApi.sectorMembers('BK0475'); // 银行
    expect(members.length, greaterThan(10));
    // 默认按涨跌幅降序。
    for (var i = 1; i < members.length; i++) {
      expect(members[i - 1].pct, greaterThanOrEqualTo(members[i].pct));
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
