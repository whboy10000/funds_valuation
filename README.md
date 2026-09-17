# 基金实时估值 Fund Valuation

一款**全平台**基金实时估值应用，一套代码同时覆盖 **macOS / Windows / Linux / iOS / Android / Web** 六端。

官方盘中估值接口（fundgz / GSZ）已下线，本应用自研实时估值引擎：以前十大重仓股持仓权重结合实时行情自算估值，并支持「重仓股实时 + 板块拟合」混合模型，盘中随时掌握净值走向。

> 数据来源：东方财富 / 天天基金公开接口。自算估值仅供盘中参考，不代表真实净值。

## 功能一览

### 基金估值
- **自研实时估值引擎**：重仓股权重 × 实时行情 × 股票仓位，官方估值下线后依然盘中可算
- **混合估值模型**：重仓股部分按持股实时价（Mark-to-Market），非重仓部分按行业板块指数拟合，合计总自研估值
- **分时估值走势**：聚合重仓股分时行情加权生成开盘至今全天曲线
- **历史净值走势**：1月 / 3月 / 6月 / 1年 / 全部区间切换
- **每日规模曲线**：场内基金 = 流通份额 × 每日收盘价（实时规模用总市值校准）；场外基金 = 最新披露份额 × 每日单位净值
- **基金详情 12 模块**：概况、经理、公司、评级、特色数据、历史净值、分红、持仓变动、行业配置、重大变动、规模变化、持有人结构
- **前十大重仓股**：实时涨跌 + 较上期变化（新进 / 增减百分比 / 持平），表头行标注披露报告期

### 持仓管理
- 录入持有金额、持有天数、持有收益（收益按当前市值反推成本）
- 每只基金显示当日估算收益、持有收益、持有收益率、持有天数、关联板块
- 加仓 / 减仓 / 交易记录
- 资产占比饼图、账户资产与当日收益汇总

### 分组与排行
- **分组标签**：支付宝 / 天天基金 / 京东金融 / 同花顺爱理财 / 微信理财 / 自定义，横向标签切换 + 组内收益小计
- **基金排行**：场内 / 场外双榜——场内 1600+ 只 ETF/LOF 按实时价排序；场外 2 万+ 只按净值日增长率排序；涨幅 / 跌幅榜与主题关键词筛选

### 行情
- **大盘行情**：A 股核心指数、13 个港股指数（恒生 / 国企 / 港股通系列）、全球指数（纳斯达克100 / 道指 / 标普 / 日经 / KOSPI / 富时）
- **3D 全球市场地球**：正交投影自绘球体，国家边界按主要指数涨跌染色，支持旋转 / 缩放，点击国家查看该国常用指数
- **板块行情**：行业 / 概念板块涨幅排行、正序倒序切换、成分股列表、主力净流入、领涨股
- **全市场涨跌分布**：上涨 / 平盘 / 下跌家数与比例条

### 其他
- 自动刷新间隔（5~60s / 关闭）、红涨绿跌切换、浅色 / 深色 / 跟随系统主题、数据导出
- 自适应布局：宽屏左侧导航栏，窄屏底部导航；前台自动刷新，后台暂停

## 支持的平台

| 平台 | 架构 | 最低系统版本 | 安装包 |
| --- | --- | --- | --- |
| Android | armeabi-v7a + arm64-v8a + x86_64（单 APK 全含） | Android 7.0（minSdk 由 Flutter 引擎决定） | `fund-valuation-android.apk` |
| iOS | arm64 | iOS 15.0 | `fund-valuation-ios-unsigned.ipa`（未签名，需自签 / 侧载） |
| Windows | x64 | Windows 10 1809+ | `fund-valuation-windows-x64.msi` 安装包 |
| macOS | Universal（Intel x86_64 + Apple Silicon arm64 单包） | macOS 10.15+ | `fund-valuation-macos-universal.dmg` |
| Linux | x64 | 主流发行版（GTK3） | `fund-valuation-linux-x64.deb` |
| Web | 任意现代浏览器 | — | 静态文件 `build/web/` 或 Docker 镜像 |

所有安装包由 GitHub Actions 自动构建，前往 [Releases](https://github.com/whboy10000/funds_valuation/releases) 下载。

## Docker 部署（Web 端）

Web 产物打包为容器镜像发布到 GHCR，服务器上一条命令运行：

```bash
docker run -d -p 8080:80 ghcr.io/whboy10000/funds_valuation:latest
```

浏览器访问 `http://<服务器IP>:8080` 即可使用。也可本地自行构建：

```bash
flutter build web --release
docker build -t fund-valuation .
docker run -d -p 8080:80 fund-valuation
```

## CI/CD

推送 `v*` 格式 tag 自动触发 [.github/workflows/release.yml](.github/workflows/release.yml)：

- 六平台并行构建（Android / Windows / Linux / macOS / iOS / Web-Docker）
- 产物自动上传到 GitHub Release
- Docker 镜像自动推送 GHCR（`2.1.1` 与 `latest` 双标签）
- macOS 构建后用 `lipo` 校验 Universal 双架构

## 技术栈

| 项 | 说明 |
| --- | --- |
| 开发语言 | Dart 3.13 |
| 框架 | Flutter 3.47（Material 3） |
| 网络 | `http` + 自研东财接口封装（批量行情 / 分时 / 日K / 板块 / 基金档案，多主机回退与限频节流） |
| 本地存储 | `shared_preferences`（自选、持仓、分组、设置） |
| Web 兼容 | `web` 包（JSONP 方式绕过无 CORS 头的接口） |
| 自绘组件 | 3D 地球（世界边界 JSON 资产 + Canvas 正交投影）、面积图、饼图、迷你分时线 |
| 质量保障 | `flutter analyze` 0 问题 + 单元测试 |

## 本地开发

```bash
git clone https://github.com/whboy10000/funds_valuation.git
cd funds_valuation
flutter pub get

flutter run                  # 默认设备
flutter run -d chrome        # Web
flutter run -d macos         # macOS
```

各平台构建命令：

| 平台 | 命令 | 产物位置 |
| --- | --- | --- |
| Web | `flutter build web --release` | `build/web/` |
| Android | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| macOS | `flutter build macos --release` | `build/macos/Build/Products/Release/基金估值.app` |
| iOS | `flutter build ios --release --no-codesign` | Xcode 工程产物（签名构建用 `flutter build ipa`） |
| Windows | `flutter build windows --release` | `build/windows/x64/runner/Release/` |
| Linux | `flutter build linux --release` | `build/linux/x64/release/bundle/` |

> Windows / Linux 需在对应平台上构建（桌面端不支持从 macOS 交叉编译），进入项目目录执行即可，无需改代码。

## 测试

```bash
flutter analyze
flutter test
```

## 免责声明

本项目仅供学习与个人参考，不构成任何投资建议。行情与基金数据来自东方财富 / 天天基金公开接口，请遵守相关服务条款，勿高频请求。
