# UI QA / Polish 开发踩坑记录

记录本次 GrandPrixReminder UI v2 与最终 UI QA 中真实遇到的问题，供后续界面和 API 联调复用。

## 1. Flutter 报 `double` 不能转 `bool?` 时，先找抛错 widget 和读取位置

Evolution 的真实 API 有 42 条升级，`confidence` 是字符串形式的分数（例如 `"0.6"`），`stale` 是 JSON 布尔值。最初错误信息容易让人怀疑新 confidence 字段，但 Flutter DTO 与 Backend `UpgradeRead`/SQLite `TEXT` 契约都吻合。

复现栈最终指向 Flutter `_ExpansibleState.initState` 从 PageStorage 读取展开状态。页面滚动用 `PageStorageKey('page-2')` 保存 double 偏移；Evolution 内多个 ExpansionTile 没有各自的 `PageStorageKey`，于是从相同存储路径把滚动偏移强转成 bool。为每个 ExpansionTile 分配单独且稳定的 PageStorageKey，保留滚动位置和展开状态，两种状态即可并存。不要捕获异常或用默认布尔值掩盖键冲突。

复现和防回归应包括：使用原始线上 JSON；先等待异步页面和 3D 资源加载；滚动；销毁页面；用相同 PageStorageBucket 返回；断言没有异常并检查所需展开状态。只实例化 DTO 不会覆盖 PageStorage 恢复路径。

## 2. Dart `setState` 回调必须同步结束

表达式形式 `setState(() => _request = _fetch())` 会把 Future 作为回调返回值，即使开发者本意只是保存 Future，debug 模式仍会报 “setState() callback argument returned a Future”。使用块体并不返回 Future：`setState(() { _request = _fetch(); });`。增量刷新和重试路径也要覆盖，不要只测首次加载。

## 3. ExpansionTile 的测试和实现依赖同一类存储键

将生产代码从普通 `ValueKey` 改成 `PageStorageKey` 后，既有测试若按旧 key 查找面板会出现 `ensureVisible` 的 “No element”。测试应查找对应的 PageStorageKey，同时验证展开行为和旧功能，而不是删掉测试步骤。

## 4. Flutter widget test 的默认字体不能代表手机字体

测试环境未显式加载字体时，中文和 Material 图标可能显示为方块；这不是应用实际设备上的字体回归。截图测试要加载仓库中的 Newsreader、Barlow、Barlow Condensed 和 Flutter Material Icons，并为中文加载可用字体回退。对长文本还要覆盖窄屏和较大系统字号。

## 5. 异步资源完成后再截图，并显式安排重绘

`pumpAndSettle` 不等待所有非 Flutter fake-async 的文件读取。CarModel 从 rootBundle 异步加载，截图测试需要在 `runAsync` 等待资源、pump 使 UI 更新，再确认目标 CustomPaint 出现。不同测试间复用 asset cache 时清理测试 bundle cache。截屏前标记 RepaintBoundary 需要重绘，可避免拿到上一个测试留下的旧图层。

## 6. API 故障与空数据不可混为一谈

本轮现场 API 中 Evolution 历史分站有真实记录，卡塔尔分站和 2025 赛季无记录；策略接口返回 503，媒体接口返回 404。测试夹具保存未经修改的响应体和状态码。成功响应中的空集合、失败响应和缓存旧数据各有不同 UI 含义；不要用样例数据、假的成功响应或宽泛 catch 让它们看起来相同。

## 7. 真实 payload 回归需要同时核对数据端和界面端

将相同分站的 en、zh-CN payload 按升级 ID 对齐，比较 confidence、status、source 集合，同时允许标题或证据译文按语言变化。历史文字置信度如 `high` 应继续显示 Unknown；只有能解析为 0 到 1 的有限数字才能用于低置信度展示。这能避免把“已存在的数据字段”和“新的显示规则”误认为 API 类型变更。

## 8. 本地 Flutter 工具链需要使用仓库隔离目录

此 Windows 工作区的 Flutter/Dart SDK、pub cache、Android SDK、Gradle home 都放在 `.tools` 下。设置 `FLUTTER_SUPPRESS_ANALYTICS=true` 与 `PUB_CACHE` 再运行测试/分析/构建，避免系统 profile 写入权限造成非代码失败。PowerShell 管道接 Python 时，为 UTF-8 文本设 `PYTHONUTF8=1`。执行测试后以测试日志的退出状态和结束汇总为准，不以外层 shell 是否及时返回判断。

本次完整执行结果记录于 [UI QA Polish 报告](ui-qa-polish.md)。
