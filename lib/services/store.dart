import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// 本地持久化：自选基金与设置。
class Store {
  static const _kFunds = 'funds.v1';
  static const _kTrades = 'trades.v1';
  static const _kRefresh = 'settings.refreshSecs';
  static const _kRedUp = 'settings.redUp';
  static const _kTheme = 'settings.themeMode';
  static const _kSort = 'settings.sortMode';

  static Future<List<FundItem>> loadFunds() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kFunds);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => FundItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFunds(List<FundItem> funds) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kFunds, jsonEncode(funds.map((e) => e.toJson()).toList()));
  }

  /// 交易记录（加仓/减仓）。
  static Future<List<TradeRecord>> loadTrades() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kTrades);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TradeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrades(List<TradeRecord> trades) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kTrades, jsonEncode(trades.map((e) => e.toJson()).toList()));
  }

  static Future<int> loadRefreshSecs() async =>
      (await SharedPreferences.getInstance()).getInt(_kRefresh) ?? 15;

  static Future<void> saveRefreshSecs(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kRefresh, v);

  static Future<bool> loadRedUp() async =>
      (await SharedPreferences.getInstance()).getBool(_kRedUp) ?? true;

  static Future<void> saveRedUp(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kRedUp, v);

  /// 0 跟随系统 / 1 浅色 / 2 深色。
  static Future<int> loadThemeMode() async =>
      (await SharedPreferences.getInstance()).getInt(_kTheme) ?? 0;

  static Future<void> saveThemeMode(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kTheme, v);

  /// 自选排序：0 自定义(置顶) / 1 估值涨幅降 / 2 估值涨幅升 / 3 市值降 / 4 名称。
  static Future<int> loadSortMode() async =>
      (await SharedPreferences.getInstance()).getInt(_kSort) ?? 0;

  static Future<void> saveSortMode(int v) async =>
      (await SharedPreferences.getInstance()).setInt(_kSort, v);
}
