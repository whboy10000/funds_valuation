# 基金实时估值（Flutter 全平台）

基于 Flutter 实现的基金实时估值应用，覆盖 **macOS / Windows / Linux / iOS / Android / Web** 六端。

## 功能

- **基金估值**：自选基金管理（搜索添加 / 置顶 / 删除）、收益汇总（今日估算收益 / 持仓市值 / 持仓收益）、
  自研实时估值引擎（重仓股权重 × 实时行情 × 股票仓位）、
  分时估值走势（聚合重仓股分时行情加权生成开盘至今全天曲线，缓存 3 分钟）、
  历史净值走势（1月/3月/6月/1年/全部）、基金经理信息、前十大重仓股实时涨跌、阶段收益率。
- **持仓管理**：添加基金时可直接录入持有金额与买入成本（长按条目可随时修改），
  列表展示每只基金的持有收益；支持按估值涨幅（升/降）、持仓市值、名称排序。
- **分组标签**：顶部横向标签（全部 / 支付宝 / 天天基金 / 京东金融 / 同花顺爱理财 / 微信理财 / 自定义），
  点击标签切换查看该分组下基金的实时估值与涨跌幅，选中分组时显示组内今日收益小计。
- **大盘行情**：A 股核心指数（上证/深成/创业板/沪深300/科创50/中证500/上证50）、
  港股指数（恒生指数 / 恒生科技 / 国企指数 / 港股通互联网 / 港股通消费 / 港股通创新药）、
  全球指数（纳指/道指/标普/日经/KOSPI/富时）、
  全市场涨跌分布（上涨/平盘/下跌 + 比例条）、指数分时图。
- **板块行情**：行业板块 / 概念板块实时涨幅排行（分页拉取全量，含下跌板块）、
  涨幅正序/倒序切换（可看涨幅最高与最低的板块）、
  涨跌家数、领涨股、主力净流入、换手率、名称筛选、板块分时图，
  板块详情展示全部成分股并支持按涨跌幅升降序排列。
- **基金排行**：全市场两万余只基金按最新披露净值日增长率排序，
  涨幅榜 / 跌幅榜一键切换，支持按股票型 / 混合型 / 指数型 / 债券型 / QDII 类型筛选，
  点击条目进入基金详情。
- **设置**：自动刷新间隔（5~60s / 关闭）、红涨绿跌切换、浅色/深色/跟随系统主题、导出自选、清空数据。
- **自适应布局**：宽屏左侧导航栏，窄屏底部导航；前台自动刷新，后台暂停。

> 说明：官方盘中估值（fundgz / GSZ）已下线，本应用估值由前十大重仓股持仓权重结合实时行情自算，
> 仅供盘中参考，不代表真实净值。数据来源：东方财富 / 天天基金公开接口。

## 构建产物

| 平台 | 命令 | 产物位置 |
| --- | --- | --- |
| Web | `flutter build web --release` | `build/web/`（任意静态服务器可部署） |
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/基金估值.app` |
| iOS | `flutter build ios --release --no-codesign`（需签名时去掉 `--no-codesign` 或用 `flutter build ipa`） | Xcode 工程产物 |
| Windows | 在 Windows 机器上执行 `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| Linux | 在 Linux 机器上执行 `flutter build linux --release` | `build/linux/x64/release/bundle/` |

> Windows / Linux 无法从 macOS 交叉编译，需在对应平台安装 Flutter SDK 后进入本目录执行构建即可（无需改代码）。

## 开发运行

```bash
flutter pub get
flutter run                  # 默认设备
flutter run -d chrome        # Web
flutter run -d macos         # macOS
```

## 测试

```bash
flutter analyze
flutter test
```
