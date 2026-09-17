import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';
import 'about_page.dart';
import 'common.dart';

/// 设置页。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.shared;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: kFloatingNavPadding),
          children: [
            const LargeTitleBar(title: '设置'),
            const _GroupCaption('刷新'),
            GroupedCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                const ListTile(
                  leading: Icon(Icons.timer_outlined),
                  title: Text('自动刷新间隔'),
                  subtitle: Text('前台运行时按间隔刷新估值与行情'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
            const _GroupCaption('显示'),
            GroupedCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('红涨绿跌'),
                  subtitle: const Text('关闭后为绿涨红跌（国际惯例）'),
                  value: app.redUp,
                  onChanged: app.setRedUp,
                ),
                RadioGroup<int>(
                  groupValue: app.themeMode,
                  onChanged: (v) => app.setThemeMode(v ?? 0),
                  child: const Column(
                    children: [
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
              ],
            ),
            const _GroupCaption('数据'),
            GroupedCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('导出自选列表'),
                  subtitle: const Text('保存为 JSON 备份文件（含持仓与交易记录）'),
                  onTap: () => _exportFunds(context),
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导入自选列表'),
                  subtitle: const Text('从 JSON 备份文件恢复，支持合并或覆盖'),
                  onTap: () => _importFunds(context),
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy),
                  title: const Text('复制基金代码'),
                  subtitle: const Text('将全部自选代码以逗号分隔复制到剪贴板'),
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
            const _GroupCaption('关于'),
            GroupedCard(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('APP 介绍'),
                  subtitle: const Text('平台适配、功能模块与估值计算原理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.tag),
                  title: Text('版本'),
                  subtitle: Text('基金实时估值 v2.1.1'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Text(
                '数据来源：东方财富 / 天天基金公开接口。'
                '盘中估值为自研计算，仅供参考，不代表真实净值。',
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导出自选为 JSON 文件。
  Future<void> _exportFunds(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final app = AppState.shared;
    if (app.funds.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('自选列表为空，无需导出')));
      return;
    }
    final n = DateTime.now();
    final stamp = '${n.year}${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}-'
        '${n.hour.toString().padLeft(2, '0')}'
        '${n.minute.toString().padLeft(2, '0')}';
    final jsonStr = app.exportFundsJson();
    try {
      // 桌面 / 移动端弹出保存位置选择；Web 端 bytes 直接触发浏览器下载。
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出自选列表',
        fileName: 'funds-backup-$stamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(jsonStr)),
      );
      // 返回 null 表示用户取消保存，不提示。
      if (uri != null) {
        messenger
            .showSnackBar(const SnackBar(content: Text('已导出 JSON 备份文件')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// 选择 JSON 文件并导入。
  Future<void> _importFunds(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: '选择自选备份文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('读取文件失败：$e')));
      return;
    }
    if (picked == null) return; // 用户取消。
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('无法读取该文件：$e')));
      return;
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('文件编码不支持，请选择 UTF-8 编码的 JSON')));
      return;
    }

    if (!context.mounted) return;
    final replace = await _chooseImportMode(context);
    if (replace == null) return; // 用户取消。

    try {
      final r = await AppState.shared.importFundsJson(raw, replace: replace);
      final mode = r.replaced ? '覆盖导入' : '合并导入';
      final msg = StringBuffer('$mode完成：共 ${r.total} 只');
      if (!r.replaced) {
        msg.write('，新增 ${r.added} 只，更新 ${r.updated} 只');
      }
      if (r.trades > 0) msg.write('，交易记录 ${r.trades} 条');
      if (r.invalid > 0) msg.write('（跳过 ${r.invalid} 条无效数据）');
      messenger.showSnackBar(SnackBar(content: Text(msg.toString())));
    } on FormatException catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
    }
  }

  /// 选择导入方式：true 覆盖 / false 合并 / null 取消。
  Future<bool?> _chooseImportMode(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入方式'),
        content: const Text(
            '合并导入：保留现有自选，相同代码以备份文件为准；\n'
            '覆盖导入：清空现有自选与交易记录后完全恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('合并导入'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖导入'),
          ),
        ],
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

class _GroupCaption extends StatelessWidget {
  const _GroupCaption(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 7),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.outline,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
