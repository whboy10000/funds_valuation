import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../services/market_api.dart';
import '../state.dart';
import 'common.dart';

/// 3D 全球市场（可嵌入子模块）：正交投影自绘球体。
///
/// - 默认自动旋转，拖动后暂停几秒再恢复，可用按钮随时开关；
/// - 支持拖动旋转（水平/垂直）、双指缩放与 +/- 按钮；
/// - 国家版图按主要指数涨跌染色（红涨绿跌，无数据为灰色）；
/// - 点击国家在底部显示该国常用指数实时行情。
class GlobeView extends StatefulWidget {
  const GlobeView({super.key});

  @override
  State<GlobeView> createState() => _GlobeViewState();
}

/// 国家点位、地理边界名与常用指数。
class _Country {
  const _Country(
      this.country, this.continent, this.lat, this.lon, this.indices,
      {this.geoNames = const []});

  final String country;
  final String continent;
  final double lat;
  final double lon;
  final List<(String, String)> indices;

  /// world.json 中对应的 feature 名称（用于版图染色）。
  final List<String> geoNames;

  static const all = <_Country>[
    _Country('中国', '亚洲', 33.5, 116.0, [
      ('1.000001', '上证指数'),
      ('0.399001', '深证成指'),
      ('0.399006', '创业板指'),
      ('1.000300', '沪深300'),
      ('1.000688', '科创50'),
    ], geoNames: ['China']),
    _Country('中国香港', '亚洲', 20.8, 115.2, [
      ('100.HSI', '恒生指数'),
      ('124.HSTECH', '恒生科技'),
      ('100.HSCEI', '国企指数'),
    ]),
    _Country('日本', '亚洲', 36.5, 139.5, [
      ('100.N225', '日经225'),
    ], geoNames: ['Japan']),
    _Country('韩国', '亚洲', 37.0, 128.2, [
      ('100.KS11', '韩国KOSPI'),
    ], geoNames: ['South Korea']),
    _Country('中国台湾', '亚洲', 23.7, 121.0, [
      ('100.TWII', '台湾加权'),
    ], geoNames: ['Taiwan']),
    _Country('新加坡', '亚洲', 1.35, 103.8, [
      ('100.STI', '海峡时报'),
    ]),
    _Country('印度尼西亚', '亚洲', -2.5, 118.0, [
      ('100.JKSE', '雅加达综合'),
    ], geoNames: ['Indonesia']),
    _Country('印度', '亚洲', 21.0, 78.0, [
      ('100.SENSEX', '孟买SENSEX'),
    ], geoNames: ['India']),
    _Country('德国', '欧洲', 51.0, 10.0, [
      ('100.GDAXI', '德国DAX'),
      ('100.SX5E', '欧洲斯托克50'),
    ], geoNames: ['Germany']),
    _Country('英国', '欧洲', 53.5, -1.8, [
      ('100.FTSE', '英国富时100'),
    ], geoNames: ['United Kingdom']),
    _Country('法国', '欧洲', 46.6, 2.5, [
      ('100.FCHI', '法国CAC40'),
      ('100.SX5E', '欧洲斯托克50'),
    ], geoNames: ['France']),
    _Country('荷兰', '欧洲', 52.3, 5.5, [
      ('100.AEX', '荷兰AEX'),
      ('100.SX5E', '欧洲斯托克50'),
    ], geoNames: ['Netherlands']),
    _Country('意大利', '欧洲', 42.8, 12.5, [
      ('100.MIB', '意大利MIB'),
      ('100.SX5E', '欧洲斯托克50'),
    ], geoNames: ['Italy']),
    _Country('西班牙', '欧洲', 40.2, -3.7, [
      ('100.IBEX', '西班牙IBEX35'),
      ('100.SX5E', '欧洲斯托克50'),
    ], geoNames: ['Spain']),
    _Country('欧盟', '欧洲', 49.6, 7.0, [
      ('100.SX5E', '欧洲斯托克50'),
    ]),
    _Country('俄罗斯', '欧洲', 58.0, 42.0, [
      ('100.RTS', '俄罗斯RTS'),
    ], geoNames: ['Russia']),
    _Country('美国', '北美洲', 39.0, -98.5, [
      ('100.DJIA', '道琼斯'),
      ('100.NDX', '纳斯达克100'),
      ('100.SPX', '标普500'),
    ], geoNames: ['United States of America']),
    _Country('加拿大', '北美洲', 56.0, -106.0, [
      ('100.TSX', '多伦多TSX'),
    ], geoNames: ['Canada']),
    _Country('墨西哥', '北美洲', 23.6, -102.0, [
      ('100.MXX', '墨西哥BOLSA'),
    ], geoNames: ['Mexico']),
    _Country('巴西', '南美洲', -10.0, -52.0, [
      ('100.BVSP', '巴西BOVESPA'),
    ], geoNames: ['Brazil']),
    _Country('澳大利亚', '大洋洲', -25.0, 134.0, [
      ('100.AORD', '澳洲普通股'),
    ], geoNames: ['Australia']),
    // 非洲暂无公开指数数据源，仅作占位。
    _Country('非洲', '非洲', 2.0, 20.0, []),
  ];

  static final _allSecids = [
    for (final c in all)
      for (final s in c.indices) s.$1,
  ];

  /// 首个有效指数涨跌幅（用于版图与点标颜色）。
  double pctOf(Map<String, Quote> quotes) {
    for (final (secid, _) in indices) {
      final p = quotes[secid]?.pct;
      if (p != null && !p.isNaN) return p;
    }
    return double.nan;
  }
}

class _GlobeViewState extends State<GlobeView>
    with SingleTickerProviderStateMixin {
  /// 国家名 → 边界环集合（用于染色）。
  Map<String, List<Float32List>> _geoRings = {};
  /// 未映射到国家的边界环（保持世界地图完整）。
  List<Float32List> _otherRings = [];

  Map<String, Quote> _quotes = {};
  bool _loading = true;
  String? _error;
  DateTime _updatedAt = DateTime.now();

  double _rot = -0.45;
  double _tilt = 0.30;
  double _scale = 1.0; // 1.0 ~ 3.2

  _Country? _selected;
  bool _autoRotate = true;
  int _userAtMs = 0; // 最近一次手动操作，稍后恢复自转
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _loadRings();
    _loadQuotes();
    _ticker = createTicker((_) {
      if (!_autoRotate || _selected != null) return;
      if (DateTime.now().millisecondsSinceEpoch - _userAtMs < 3500) return;
      setState(() => _rot += 0.0022);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadRings() async {
    try {
      final text = await rootBundle.loadString('assets/world.json');
      final data = jsonDecode(text) as Map<String, dynamic>;
      final geo = <String, List<Float32List>>{};
      final others = <Float32List>[];
      final known = {
        for (final c in _Country.all) ...c.geoNames,
      };
      for (final f in data['countries'] as List) {
        final m = f as Map<String, dynamic>;
        final name = m['name'] as String;
        final rings = <Float32List>[];
        for (final ring in m['rings'] as List) {
          final pts = (ring as List).cast<List>();
          final flat = Float32List(pts.length * 2);
          for (var i = 0; i < pts.length; i++) {
            flat[i * 2] = (pts[i][0] as num).toDouble();
            flat[i * 2 + 1] = (pts[i][1] as num).toDouble();
          }
          rings.add(flat);
        }
        if (known.contains(name)) {
          geo.update(name, (v) => [...v, ...rings],
              ifAbsent: () => rings);
        } else {
          others.addAll(rings);
        }
      }
      if (!mounted) return;
      setState(() {
        _geoRings = geo;
        _otherRings = others;
      });
    } catch (_) {
      // 边界数据加载失败时退化为网格球体。
    }
  }

  Future<void> _loadQuotes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quotes = await MarketApi.quotes(_Country._allSecids);
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _loading = false;
        _updatedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '全球指数获取失败，请检查网络';
      });
    }
  }

  // 正交投影：经纬度 → 旋转（水平 + 倾角）→ 球面坐标。
  static (double, double, double) _projectLL(
      double latDeg, double lonDeg, double rot, double tilt) {
    final lon = lonDeg * math.pi / 180 + rot;
    final lat = latDeg * math.pi / 180;
    final x = math.cos(lat) * math.sin(lon);
    final y = math.sin(lat);
    final z = math.cos(lat) * math.cos(lon);
    final ct = math.cos(tilt), st = math.sin(tilt);
    final y2 = y * ct - z * st;
    final z2 = y * st + z * ct;
    return (x, y2, z2);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseRot = _rot;
    _baseTilt = _tilt;
    _baseScale = _scale;
    _userAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  double _baseRot = 0, _baseTilt = 0, _baseScale = 1;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _userAtMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      if (d.pointerCount >= 2) {
        _scale = (_baseScale * d.scale).clamp(1.0, 3.2);
      } else {
        _rot = _baseRot + d.focalPointDelta.dx * 0.008;
        _tilt = (_baseTilt - d.focalPointDelta.dy * 0.006)
            .clamp(-1.2, 1.2);
      }
    });
  }

  void _onTapUp(TapUpDetails d, double r, double cx, double cy) {
    _userAtMs = DateTime.now().millisecondsSinceEpoch;
    _Country? hit;
    var best = 26.0 * math.max(1, _scale * 0.8);
    for (final c in _Country.all) {
      final (x, y, z) = _projectLL(c.lat, c.lon, _rot, _tilt);
      if (z <= 0) continue;
      final sx = cx + x * r, sy = cy - y * r;
      final dist = math.sqrt(math.pow(d.localPosition.dx - sx, 2) +
          math.pow(d.localPosition.dy - sy, 2));
      if (dist < best) {
        best = dist;
        hit = c;
      }
    }
    setState(() => _selected = hit);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final r =
                            math.min(c.maxWidth, c.maxHeight) / 2 * 0.82;
                        final cx = c.maxWidth / 2, cy = c.maxHeight / 2;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: (_) {},
                          onTapUp: (d) =>
                              _onTapUp(d, r * _scale, cx, cy),
                          child: CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _GlobePainter(
                              rot: _rot,
                              tilt: _tilt,
                              scale: _scale,
                              geoRings: _geoRings,
                              otherRings: _otherRings,
                              quotes: _quotes,
                              redUp: AppState.shared.redUp,
                              dark: dark,
                              surface: scheme.surfaceContainerLow,
                              onSurface: scheme.onSurface,
                              selected: _selected,
                              project: _projectLL,
                            ),
                          ),
                        );
                      },
                    ),
                    // 控制按钮列（缩放/旋转/自转开关）。
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Column(
                        children: [
                          _ctrlBtn(context, Icons.add, '放大', () =>
                              setState(() => _scale =
                                  (_scale + 0.3).clamp(1.0, 3.2))),
                          const SizedBox(height: 6),
                          _ctrlBtn(context, Icons.remove, '缩小', () =>
                              setState(() => _scale =
                                  (_scale - 0.3).clamp(1.0, 3.2))),
                          const SizedBox(height: 6),
                          _ctrlBtn(context, Icons.rotate_left, '左旋',
                              () => setState(() => _rot -= 0.35)),
                          const SizedBox(height: 6),
                          _ctrlBtn(context, Icons.rotate_right, '右旋',
                              () => setState(() => _rot += 0.35)),
                          const SizedBox(height: 6),
                          _ctrlBtn(
                              context,
                              _autoRotate
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              _autoRotate ? '停止自转' : '开启自转',
                              () => setState(
                                  () => _autoRotate = !_autoRotate)),
                          const SizedBox(height: 6),
                          _ctrlBtn(context, Icons.refresh, '重置视角', () =>
                              setState(() {
                                _rot = -0.45;
                                _tilt = 0.30;
                                _scale = 1.0;
                                _selected = null;
                              })),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildBottom(scheme, h < 260),
            ],
          ),
        );
      },
    );
  }

  Widget _ctrlBtn(
      BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tip,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child:
                Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(ColorScheme scheme, bool compact) {
    final sel = _selected;
    final list = <Widget>[];
    if (sel != null) {
      if (sel.indices.isEmpty) {
        list.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('该区域暂无公开指数数据源',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ));
      } else {
        for (final (secid, name) in sel.indices) {
          final q = _quotes[secid];
          list.add(Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(q == null ? '--' : fmtPrice(q.price),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 1),
                PctText(q?.pct ?? double.nan, fontSize: 12),
              ],
            ),
          ));
        }
      }
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, compact ? 6 : 9, 14, compact ? 8 : 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sel == null ? Icons.public : Icons.location_on,
                  size: 14, color: scheme.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  sel == null
                      ? (_error ??
                          (_loading
                              ? '全球指数加载中…'
                              : '更新于 ${_hhmmss(_updatedAt)} · 拖动旋转 · 双指/按钮缩放 · 点击国家查看指数'))
                      : '${sel.country} · ${sel.continent}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: _error != null
                          ? scheme.error
                          : scheme.outline),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '刷新行情',
                icon: Icon(Icons.refresh,
                    size: 17, color: scheme.onSurfaceVariant),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _loadQuotes,
              ),
            ],
          ),
          if (sel != null)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: list,
              ),
            ),
        ],
      ),
    );
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

typedef _ProjFn = (double, double, double) Function(
    double lat, double lon, double rot, double tilt);

class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.rot,
    required this.tilt,
    required this.scale,
    required this.geoRings,
    required this.otherRings,
    required this.quotes,
    required this.redUp,
    required this.dark,
    required this.surface,
    required this.onSurface,
    required this.selected,
    required this.project,
  });

  final double rot;
  final double tilt;
  final double scale;
  final Map<String, List<Float32List>> geoRings;
  final List<Float32List> otherRings;
  final Map<String, Quote> quotes;
  final bool redUp;
  final bool dark;
  final Color surface;
  final Color onSurface;
  final _Country? selected;
  final _ProjFn project;

  static const _upTop = Color(0xFFE53935), _upDeep = Color(0xFF9E0B0B);
  static const _dnTop = Color(0xFF43A047), _dnDeep = Color(0xFF0B6B2F);

  Color _deepColor(double pct) {
    if (pct.isNaN || pct == 0) return const Color(0xFF9E9E9E);
    final up = pct > 0;
    final isUp = redUp ? up : !up;
    final from = isUp ? _upTop : _dnTop;
    final to = isUp ? _upDeep : _dnDeep;
    return Color.lerp(from, to, (pct.abs() / 3).clamp(0.15, 1.0))!;
  }

  /// 国家版图填充色：按涨跌染色，无数据为灰，选中加深。
  Color _countryFill(double pct, bool isSel) {
    final a = (pct.isNaN ? 0.14 : 0.16 + 0.30 * (pct.abs() / 3).clamp(0.0, 1.0)) +
        (isSel ? 0.16 : 0);
    if (pct.isNaN) {
      return (dark ? Colors.white : Colors.black).withValues(alpha: a);
    }
    return _deepColor(pct).withValues(alpha: a);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 * 0.82 * scale;
    final cx = size.width / 2, cy = size.height / 2;

    // 大气光晕 + 球体底色（跟随主题）。
    canvas.drawCircle(
        Offset(cx, cy),
        r * 1.12,
        Paint()
          ..shader = RadialGradient(colors: [
            schemeless(primaryHalo),
            const Color(0x00FFFFFF),
          ]).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.12)));
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: dark
                ? const [Color(0xFF243356), Color(0xFF16203A)]
                : const [Color(0xFFFFFFFF), Color(0xFFD9E4F6)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)));

    final borderCol = dark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF6B7C99).withValues(alpha: 0.55);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = borderCol;
    final unclaimed = (dark ? Colors.white : Colors.black)
        .withValues(alpha: dark ? 0.08 : 0.06);

    // 国家边界 + 涨跌染色。
    final drawnRings = <List<Float32List>, Color>{};
    for (final c in _Country.all) {
      final rings = [
        for (final n in c.geoNames) ...?geoRings[n],
      ];
      if (rings.isEmpty) continue;
      final isSel = identical(c, selected);
      drawnRings[rings] = _countryFill(c.pctOf(quotes), isSel);
    }
    for (final entry in drawnRings.entries) {
      _paintRings(canvas, entry.key, entry.value, border, r, cx, cy,
          selected: true);
    }
    // 未映射国家：淡填充保持地图完整。
    _paintRings(canvas, otherRings, unclaimed, border, r, cx, cy);

    // 经纬网格（弱化）。
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = (dark ? const Color(0xFF6E93D8) : const Color(0xFF8FA6C8))
          .withValues(alpha: 0.22);
    for (var la = -60; la <= 60; la += 30) {
      final path = Path();
      var started = false;
      for (var lo = 0; lo <= 360; lo += 6) {
        final (x, y, z) = project(la.toDouble(), lo.toDouble(), rot, tilt);
        if (z <= 0) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(cx + x * r, cy - y * r);
          started = true;
        } else {
          path.lineTo(cx + x * r, cy - y * r);
        }
      }
      canvas.drawPath(path, grid);
    }

    // 球缘描边。
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = (dark ? Colors.white : Colors.black)
              .withValues(alpha: 0.22));

    // 国家标记 + 防重叠标签。
    final labelColor = onSurface;
    final marks = <(_Country, Offset, double)>[];
    for (final c in _Country.all) {
      final (x, y, z) = project(c.lat, c.lon, rot, tilt);
      if (z <= 0) continue;
      marks.add((c, Offset(cx + x * r, cy - y * r), z));
    }
    marks.sort((a, b) => b.$3.compareTo(a.$3)); // 前面优先占位

    final occupied = <Rect>[];
    for (final (c, p, z) in marks) {
      final pct = c.pctOf(quotes);
      final color = _deepColor(pct);
      final depth = z.clamp(0.0, 1.0);
      final mag = pct.isNaN ? 0.0 : (pct.abs() / 3).clamp(0.08, 1.0);
      final dotR = (3.2 + 3.4 * mag) * math.max(1, scale * 0.8);

      canvas.drawCircle(p, dotR * 2.3,
          Paint()..color = color.withValues(alpha: 0.16 * depth));
      canvas.drawCircle(p, dotR,
          Paint()..color = color.withValues(alpha: 0.55 + 0.45 * depth));
      if (identical(c, selected)) {
        canvas.drawCircle(p, dotR + 4.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = labelColor);
      }

      // 标签防重叠：四方向尝试，全占则只画点。
      final tp = TextPainter(
        text: TextSpan(
            text: '${c.country} ',
            style: TextStyle(
                fontSize: 10.5 * math.max(1, scale * 0.85),
                fontWeight: FontWeight.w600,
                color: labelColor.withValues(alpha: 0.55 + 0.45 * depth)),
            children: [
              if (!pct.isNaN)
                TextSpan(
                    text: pctText(pct),
                    style: TextStyle(
                        fontSize: 10.5 * math.max(1, scale * 0.85),
                        fontWeight: FontWeight.w600,
                        color: color)),
            ]),
        textDirection: TextDirection.ltr,
      )..layout();
      final half = Size(tp.width / 2, tp.height / 2);
      final candidates = [
        Offset(p.dx + dotR + 5 + half.width, p.dy),
        Offset(p.dx - dotR - 5 - half.width, p.dy),
        Offset(p.dx, p.dy + dotR + 4 + half.height),
        Offset(p.dx, p.dy - dotR - 4 - half.height),
      ];
      Offset? placed;
      for (final cand in candidates) {
        final rect = Rect.fromCenter(
            center: cand, width: tp.width + 4, height: tp.height + 2);
        final collides =
            occupied.any((o) => o.overlaps(rect.deflate(1)));
        if (!collides) {
          occupied.add(rect);
          placed = cand;
          break;
        }
      }
      if (placed != null) {
        tp.paint(canvas, placed - Offset(half.width, half.height));
      }
    }
  }

  Color get primaryHalo =>
      dark ? const Color(0x303B82F6) : const Color(0x225B8DEF);

  static Color schemeless(Color c) => c;

  /// 绘制一组边界环：正面小环填充，跨边界的逐段描边。
  void _paintRings(Canvas canvas, List<Float32List> rings, Color fill,
      Paint border, double r, double cx, double cy,
      {bool selected = false}) {
    for (final ring in rings) {
      final n = ring.length ~/ 2;
      if (n < 4) continue;
      var minLon = 1e9, maxLon = -1e9;
      var allFront = true;
      for (var i = 0; i < n; i++) {
        final lon = ring[i * 2], lat = ring[i * 2 + 1];
        minLon = math.min(minLon, lon);
        maxLon = math.max(maxLon, lon);
        if (project(lat, lon, rot, tilt).$3 <= 0) allFront = false;
      }
      if (allFront && maxLon - minLon < 150) {
        final path = Path();
        for (var i = 0; i < n; i++) {
          final (x, y, _) = project(ring[i * 2 + 1], ring[i * 2], rot, tilt);
          final sx = cx + x * r, sy = cy - y * r;
          if (i == 0) {
            path.moveTo(sx, sy);
          } else {
            path.lineTo(sx, sy);
          }
        }
        path.close();
        if (fill.a > 0) canvas.drawPath(path, Paint()..color = fill);
        if (selected) {
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = Colors.white.withValues(alpha: 0.85));
        } else {
          canvas.drawPath(path, border);
        }
      } else {
        final path = Path();
        var started = false;
        for (var i = 0; i < n; i++) {
          final lat = ring[i * 2 + 1], lon = ring[i * 2];
          final (x, y, z) = project(lat, lon, rot, tilt);
          if (z <= 0) {
            started = false;
            continue;
          }
          final sx = cx + x * r, sy = cy - y * r;
          if (!started) {
            path.moveTo(sx, sy);
            started = true;
          } else {
            path.lineTo(sx, sy);
          }
        }
        canvas.drawPath(path, border);
      }
    }
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      old.rot != rot ||
      old.tilt != tilt ||
      old.scale != scale ||
      old.geoRings != geoRings ||
      old.otherRings != otherRings ||
      old.quotes != quotes ||
      old.selected != selected ||
      old.redUp != redUp ||
      old.dark != dark;
}
