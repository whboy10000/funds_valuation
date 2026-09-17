import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';

/// 设置页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
          children: [
            _Group(
              title: '刷新',
              children: [
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.timer_outlined),
                  title: Text('自动刷新间隔'),
                  subtitle: Text('前台运行时按间隔刷新估值与行情'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final v in const [0, 5, 10, 15, 30, 60])
                        ChoiceChip(
                          label: Text(v == 0 ? '关闭' : '${v}s'),
                          selected: app.refreshSecs == v,
                          onSelected: (_) => app.setRefreshSecs(v),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Group(
              title: '显示',
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('红涨绿跌'),
                  subtitle: const Text('关闭后为绿涨红跌（国际惯例）'),
                  value: app.redUp,
                  onChanged: app.setRedUp,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: RadioGroup<int>(
                    groupValue: app.themeMode,
                    onChanged: (v) => app.setThemeMode(v ?? 0),
                    child: Column(
                      children: const [
                        RadioListTile<int>(
                          secondary: Icon(Icons.brightness_6_outlined),
                          title: Text('跟随系统'),
                          value: 0,
                        ),
                        RadioListTile<int>(
                          secondary: Icon(Icons.light_mode_outlined),
                          title: Text('浅色模式'),
                          value: 1,
                        ),
                        RadioListTile<int>(
                          secondary: Icon(Icons.dark_mode_outlined),
                          title: Text('深色模式'),
                          value: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Group(
              title: '数据',
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('导出自选列表'),
                  subtitle: const Text('复制基金代码到剪贴板'),
                  onTap: () async {
                    final codes = app.funds.map((f) => f.code).join(',');
                    await Clipboard.setData(ClipboardData(text: codes));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制到剪贴板')));
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: Text('清空自选',
                      style: TextStyle(color: scheme.error)),
                  onTap: () => _confirmClear(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Group(
              title: '关于',
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('基金实时估值 v1.0.0',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      Text(
                        '数据来源：东方财富 / 天天基金公开接口。\n\n'
                        '由于官方盘中估值功能已下线，本应用的实时估值为自研计算：'
                        '基于基金前十大重仓股的持仓权重与其实时行情，'
                        '结合最新披露的股票仓位加权推算，'
                        '仅供盘中参考，不代表真实净值。\n\n'
                        '估值准确性受持仓披露滞后影响，'
                        '对指数型、高仓位基金误差较小，'
                        '对调仓频繁或低仓位基金误差较大。',
                        style: TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空自选'),
        content: const Text('将删除全部自选基金与持仓记录，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () {
              AppState.shared.clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary)),
          ),
          ...children,
        ],
      ),
    );
  }
}
