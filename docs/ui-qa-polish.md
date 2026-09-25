# GrandPrixReminder UI QA / Polish — 2026-09-25

本轮范围：修复 Evolution runtime error，压缩 Calendar 信息密度，统一中英文显示，并检查现有页面。Home 核心布局、API 路由、生产数据和 3D 渲染系统未在本轮修改。工作区已有的 UI v2 改动保留。

## P0：Evolution 崩溃根因

使用真实 API 的 2026 赛季 payload（42 条升级）重现：进入 Evolution → 滚动 → 离开页面 → 返回。修改前英文和中文均能触发同一异常。

```text
type 'double' is not a subtype of type 'bool?' in type cast
#0 _ExpansibleState.initState
   package:flutter/src/widgets/expansible.dart:383:58
ExpansionTile
   mobile/lib/features/evolution/car_viewer.dart:780:13
ExpansionTile
   mobile/lib/features/evolution/car_viewer.dart:841:13
```

以上为修复前的应用行号；完整复现日志保存在 `.tools/ui-qa/repro.log`。

`app.dart` 的滚动页面使用 `PageStorageKey('page-2')`。Car archive、Viewer tools 没有独立 PageStorageKey，Heritage 只有普通 ValueKey，因此它们读取了与父滚动页面相同的存储路径。滚动位置是 double，Expansible 恢复展开状态时将它转换成 bool，触发异常。展开状态也可能反向污染滚动位置。

修复：为三个折叠面板分别设置 `car-archive`、`car-tools`、`heritage-{team}` 的 PageStorageKey。保留展开状态与滚动位置各自的持久化行为；没有 catch、布尔强转兜底或隐藏面板。附带修复 Evolution 刷新回调返回 Future 导致的 Flutter debug assertion；Briefing 同类重试回调也改为同步 setState 块。

### confidence / 历史数据核对

| 层 | 真实契约 | 验证 |
| --- | --- | --- |
| SQLite `upgrades.confidence` | TEXT | 历史 `high`、`0.6`、写入数值 `0.75` 后读取均保持字符串 |
| Backend `UpgradeRead.confidence` | str | 原始 API payload 通过模型校验 |
| API `confidence` | 数值字符串，例如 `"0.6"` | en / zh-CN 相同升级的分数、状态和来源相同 |
| Flutter `UpgradeEntry.confidence` | String | 页面只解析有效有限的 0–1 分数来显示置信度 |
| `stale` | bool | Backend / JSON / Flutter 一致 |
| `low_confidence` | 当前协议没有该字段 | Low 是显示层对数值分数的现有判断，不是 bool DTO 字段 |

证据没有显示 Backend schema 或历史数据类型错误，因此无需数据迁移或修改稳定 API。历史非数值标签继续显示 Unknown；没有将其虚构为数值置信度。新增 Backend 测试覆盖历史存储值及所有真实 snapshot 的类型契约。

## P1：Calendar before / after

| 项目 | Before | After |
| --- | --- | --- |
| 默认顺序 | 原始赛季顺序，已完成赛事占据顶部 | 未完成赛事在前；组内按 Round 排序 |
| 已完成优先 | 无 | 复选框“优先查看已完成的比赛”；勾选后交换两组，组内仍按 Round 排序 |
| 每站内容 | 站名、状态、赛道、日期、冠军、车队、最快圈、时间/圈数、查看详情文字 | Round、站名、赛道、日期、冠军或赛事状态、轻量箭头 |
| 详情入口 | 单独一行“查看详情” | 整行可点，保留无障碍详情提示 |
| Spoiler-Free | 隐藏成绩并在列表放揭晓按钮 | 列表显示 Results hidden；GP Detail 保留完整揭晓流程 |
| 密度 | 每站多层正文堆叠 | 390×844、正常字号、预留顶部栏和底部导航后，首屏完整显示 5 条 |

最快圈、圈数、车队、完整赛果及分析继续保留在 GP Detail。长赛道名在列表单行省略，可通过 tooltip 或详情查看；放大字体时行高自然扩展。

## P1 / P2：视觉与本地化

- Evolution 两种语言继续复用 EditorialHeader、EditorialRow、CarViewer，保持相同字号角色、spacing、divider 和组件结构。
- 新增轻量提示 `Drag · Pinch · Tap component` / `拖动旋转 · 双指缩放 · 轻点部件`。
- 补齐新增控件、车队标签和 Barcelona 名称本地化；对组合车队/状态标签逐段翻译。
- 无升级的分站明确显示空状态，同时保留 CarViewer。
- Settings 语言标题使用现有红色 metadata 层级，并压缩分隔线上下留白。
- GP Detail 成绩行垂直 padding 从 20 调为 16；完整信息和操作保留。
- Briefing 保持现有 editorial 布局；仅修复上述重试回调。
- 3D 的 Standard/Technical、5 views、Timeline、Exploded、Focus、来源、对比及既有 Ghost Compare 可用性约束保留。

## 本轮具体修改文件

| 文件 | 内容 |
| --- | --- |
| `mobile/lib/features/evolution/car_viewer.dart` | 三个 PageStorageKey、可见的交互提示 |
| `mobile/lib/features/evolution/evolution_page.dart` | 刷新回调、车队标签本地化、空范围提示 |
| `mobile/lib/features/evolution/component_explorer.dart` | 车队/状态组合标签本地化 |
| `mobile/lib/features/races/races_page.dart` | 紧凑赛事行、两组排序、已完成优先复选框 |
| `mobile/lib/features/races/race_detail_page.dart` | 成绩行留白 |
| `mobile/lib/features/briefing/briefing_page.dart` | 同步重试回调 |
| `mobile/lib/features/settings/settings_page.dart` | 标题层级与留白 |
| `mobile/lib/core/language.dart` | 新增文案翻译 |
| `mobile/lib/l10n/app_en.arb`, `app_zh.arb`, `app_zh_CN.arb` | 重新生成的文案目录 |
| `mobile/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`, `localized_catalog.dart` | 重新生成的本地化代码 |
| `mobile/test/evolution_payload_test.dart` | 真实数据、存储恢复、历史/无数据、低置信度测试 |
| `mobile/test/ui_qa_test.dart` | 真实数据 Calendar 排序/密度/导航/防剧透与各页双语布局 |
| `mobile/test/car_viewer_test.dart`, `race_detail_test.dart` | 适配新的存储键和整行入口，保留业务断言 |
| `mobile/test/f1_layout_test.dart` | 测试赛历使用不同分站 ID |
| `mobile/test/fixtures/` | 原始 API snapshots 与来源/status 说明 |
| `backend/tests/test_evolution.py` | 历史 confidence 存储契约 |
| `backend/tests/test_evolution_payload_contract.py` | 真实 API / Backend schema / 双语证据一致性 |
| `docs/ui-qa-polish.md` | 本报告 |

## 验证结果

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：64 项全部通过。
- Backend `python -m unittest discover -s tests -v`：79 项全部通过。
- `scripts/build-android.ps1`：Debug APK 构建成功，产物为 `mobile/build/app/outputs/flutter-apk/app-debug.apk`（使用现有 test API 配置）。
- 真实 API snapshots：en / zh-CN；2026 赛季、历史澳大利亚站、无升级的卡塔尔站、2025 空赛季；低置信度与原始来源。
- Widget 布局：390×844 正常字号，以及 320 宽 / 1.6 倍字体；现有测试还覆盖横屏、2 倍字体、3D 交互及来源追踪。
- 实际 API 的 strategy 返回 503、media 返回 404：保留真实不可用状态，不以样例数据代替。

日志：`.tools/ui-qa/analyze-final.log`、`flutter-all-final.log`、`backend.log`。双语截图位于 `.tools/ui-qa/`，包括 Calendar 两种排序、Evolution、Briefing、GP Detail、Settings。

验证采用真实 HTTP response replay 的 Flutter widget 渲染与截图。3D widget 测试使用既有 Canvas 路径；本轮没有进行 Android 真机 GLTF/GPU 视觉验收，也未部署生产服务。
