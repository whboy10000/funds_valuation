import 'package:flutter/material.dart';

/// APP 介绍页：平台适配、功能模块、估值计算原理。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('APP 介绍')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          // 头部标识。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Icon(Icons.trending_up,
                    size: 44, color: Color(0xFFE6221E)),
                const SizedBox(height: 10),
                const Text('基金实时估值',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  '全平台基金盘中估值与行情助手',
                  style: TextStyle(fontSize: 12.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            icon: Icons.info_outline,
            title: '关于本应用',
            child: const Text(
              '基金实时估值是一款基于 Flutter 打造的跨平台基金工具，'
              '覆盖自选基金盘中实时估值、持仓收益管理、大盘指数行情、'
              '行业板块动向以及场内 / 场外 / 指数排行榜。\n\n'
              '在基金公司官方盘中估值陆续下线后，本应用采用自研估值引擎，'
              '依据公开披露的基金持仓与实时行情独立估算，数据透明、计算可追溯，'
              '所有自选数据仅保存在本机，不上传任何服务器。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.devices_outlined,
            title: '全平台适配',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '一套代码同时适配六大平台，手机、平板、电脑与浏览器均可使用，'
                  '宽屏自动切换导航栏布局。',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _PlatformChip(icon: Icons.phone_iphone, label: 'iOS'),
                    _PlatformChip(icon: Icons.android, label: 'Android'),
                    _PlatformChip(icon: Icons.laptop_mac, label: 'macOS'),
                    _PlatformChip(
                        icon: Icons.desktop_windows_outlined,
                        label: 'Windows'),
                    _PlatformChip(
                        icon: Icons.terminal_outlined, label: 'Linux'),
                    _PlatformChip(icon: Icons.language, label: 'Web'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.dashboard_outlined,
            title: '功能模块',
            child: Column(
              children: const [
                _FeatureRow(
                  icon: Icons.query_stats,
                  title: '盘中实时估值',
                  desc: '重仓股实时行情驱动的估算涨幅、估算净值与分时走势',
                ),
                _FeatureRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '持仓收益管理',
                  desc: '持有金额 / 成本 / 分组 / 加减仓记录，自动计算持有天数与盈亏',
                ),
                _FeatureRow(
                  icon: Icons.candlestick_chart_outlined,
                  title: '大盘指数行情',
                  desc: 'A股与港股主流指数实时点位、涨跌分布与分时趋势',
                ),
                _FeatureRow(
                  icon: Icons.grid_view_outlined,
                  title: '行业板块',
                  desc: '行业 / 概念板块涨跌幅排行、板块成分股与基金关联板块',
                ),
                _FeatureRow(
                  icon: Icons.leaderboard_outlined,
                  title: '基金与指数排行',
                  desc: '场内基金、场外基金及 A股 / 港股指数三大涨幅榜',
                ),
                _FeatureRow(
                  icon: Icons.cloud_download_outlined,
                  title: '备份与个性化',
                  desc: '自选列表 JSON 导入导出、红涨绿跌切换、深浅色主题',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.calculate_outlined,
            title: '估值是如何计算的',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本应用采用自研的「混合估值引擎 V2」：'
                  '已披露的重仓股按真实行情精确计算，未披露的长尾持仓'
                  '按基金主行业的板块涨幅拟合，同时剥离现金仓位。',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '估算涨幅 = [ Σ(重仓股权重ᵢ × 个股实时涨幅ᵢ)\n'
                    '             + 剩余股票占比 × 主行业板块涨幅 ] ÷ 100\n'
                    '估算净值 = 昨日单位净值 × (1 + 估算涨幅)',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.7,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _Bullet('重仓股部分：取基金定期报告披露的前十大重仓股'
                    '及其持仓权重，按各股盘中实时涨跌幅加权求和。'),
                const _Bullet('剩余股票部分：股票总仓位减去重仓权重和后的长尾'
                    '持仓，以基金第一大配置行业对应的行业板块实时涨幅拟合。'),
                const _Bullet('现金剥离：债券、现金等非股票仓位（100% − 股票仓位）'
                    '不计入涨跌贡献，避免虚增波动。'),
                const _Bullet('估算分时：聚合重仓股盘中分时，按权重合成基金当日'
                    '估值走势曲线。'),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '准确性说明：基金季报只披露前十大重仓股且存在滞后，'
                    '指数型、高仓位基金误差较小；调仓频繁、低仓位或重仓集中度低的'
                    '主动基金误差可能较大。盘中估值仅供参考，不代表真实净值，'
                    '实际净值以基金公司披露为准。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.storage_outlined,
            title: '数据来源',
            child: const Text(
              '行情、净值与持仓数据来自东方财富 / 天天基金公开接口。\n\n'
              '本应用不提供任何投资建议，市场有风险，投资需谨慎。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('版本 v2.1.1',
                style: TextStyle(fontSize: 11.5, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
