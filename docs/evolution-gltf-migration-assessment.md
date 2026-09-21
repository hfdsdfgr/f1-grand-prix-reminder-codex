# Evolution：glTF 渲染器接入评估

评估目标：是否用 `flutter_scene`（Flutter GPU / glTF）替换现有 Flutter Canvas 面深度排序渲染器，以解除 `docs/evolution-prototype-phase1.md` 第 47 行记录的前置条件——「进入透明、爆炸、对比阶段前应采用带深度缓冲的 glTF 渲染器，并保留现有输入控制参数，不能靠增加面排序补丁代替深度测试」。

本文件是评估与方案，不是实施记录。**尚未改动任何生产代码。**

## 1. 结论

**技术上可行，且本机已验证。** 建议按增量方式接入，保留现有 Canvas 渲染器作为回退，分四个阶段推进。

## 2. 环境事实（本机实测，非推断）

| 项 | 值 |
|---|---|
| Flutter | 3.47.4 stable（revision 9584c6713b，2026-09-10） |
| Dart | 3.13.3 |
| flutter_scene 最新版 | 0.23.0（2026-08-25 发布） |
| flutter_scene 要求 | `flutter: >=3.47.0`，`sdk: ^3.10.0` |

版本要求与本机 Flutter **精确匹配**（3.47.4 ≥ 3.47.0）。这不是巧合可依赖的宽松匹配，而是该包的硬门槛。

验证记录：

1. `flutter pub add flutter_scene` 在临时工程中解析成功，拉入 21 个依赖，含 `flutter_gpu 0.0.0 from sdk flutter`、`flutter_gpu_shaders 0.5.2`、`scene 0.3.0`、`hooks 2.0.2`。
2. 用 `CuboidGeometry` + `PhysicallyBasedMaterial` + `SceneView` + `PerspectiveCamera` 写了一个最小工程，`flutter build web` 输出 **`√ Built build\web`（127.1s）**，且 Wasm dry run 成功。
3. 因此「能在本机编译」已排除，不再属于风险项。

## 3. 能力对照

规范与原型对渲染层的要求，逐条对照 flutter_scene 0.23.0 的实际能力：

| 需求（来源） | flutter_scene 能力 | 判定 |
|---|---|---|
| 带深度缓冲的 glTF 渲染（原型报告 L47） | Flutter GPU + Impeller 真深度缓冲 | ✅ |
| 13 个独立可寻址 Mesh（规范 L355-377） | glTF 节点名保留（`parser.dart:168 GltfNode(name: j['name'])`），`Node.name` 可读 | ✅ |
| 点击选中部件 | `Scene.raycast(Ray)` → `SceneRaycastHit`（`raycast.dart:84`）；`Camera.screenPointToRay`（`camera.dart:80`）做屏幕→射线 | ✅ |
| Highlight / 去强调其余部件 | 逐 `Node` 材质覆盖 | ✅ |
| Exploded View（规范 Phase 2 #11） | `Node.position/rotation/scale/localTransform` 独立变换；需自行实现平滑过渡 | ✅ 需自建 |
| 透明 / Ghost Compare（规范 Phase 3 #17） | 真深度缓冲后可可靠叠加 | ✅ 前置条件解除 |
| 按需加载、退出释放、仅加载当前车型 | `Scene` + `Node` 增删；`.fsceneb` 构建期预转换 | ✅ |
| 屏幕阅读器语义 | 包内提供语义暴露与场景 raycast 语义节点 | ✅ 优于现状 |
| 保留现有输入手感 | 输入层在 Flutter 手势层，与渲染器无关 | ✅ 与规范「禁止重新设计」不冲突 |

关键结论：**交互参数（0.01×speed 灵敏度、0.5–3 倍缩放、4px 拖动阈值）属于手势层，不属于渲染层，因此更换渲染器不需要也不应该改动它们。** 这一点是该迁移能同时满足「换渲染器」与「禁止重新设计手感」两条硬约束的原因。

## 4. 必须前置知晓的限制

### 4.1 平台支持与原生开关

flutter_scene 在原生平台依赖 Flutter GPU，**默认关闭，每个平台需显式开启一次**：

| 平台 | 状态 | 需要做什么 |
|---|---|---|
| Web | 🟢 支持 | **无需任何开关**。包自带 WebGL2 后端，在 CanvasKit 与 Skwasm 下均可运行 |
| Android | 🟢 支持 | `AndroidManifest.xml` 的 `<application>` 内加 `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true"/>` |
| iOS | 🟢 支持 | `Info.plist` 加 `<key>FLTEnableFlutterGPU</key><true/>` |
| Windows / Linux | 🟢 支持 | 需在 runner 的 `DartProject` 上设置；**发布版需 Flutter 3.47.1**（3.47.0 无此设置） |

本仓库现状（已核查）：`mobile/android/app/src/main/AndroidManifest.xml` 与 `mobile/ios/Runner/Info.plist` **均未包含**上述开关，需要新增。

对本项目的直接影响：

- **Web 无成本**，与 `flutter run -d chrome --web-port=3000` 的开发流程兼容。
- **Android / iOS 需改平台清单**，且这是 Flutter GPU 的启用开关，属于工程性变更，应由人工审查后提交。

### 4.2 包成熟度

README 自述：**pre-1.0，小版本可能带破坏性变更**。0.23.0 距本机 Flutter 3.47.4 的发布时间很近，说明该包紧跟 Flutter 主干。

处置：在 `pubspec.yaml` 中**固定精确版本**（`flutter_scene: 0.23.0`，不用 `^`），避免 `pub upgrade` 悄悄引入破坏性变更。这与本项目「缓存与来源可追溯」的一贯取向一致。

### 4.3 GLB 的 `extras.anchor` 不会传入 Flutter

已核查 `flutter_scene` 的 glTF 导入器：仅解析 `extras.targetNames`（用于 morph target 名称，`parser.dart:229`），**节点级 `extras` 不被保留**。而 `universal-car.glb` 的 13 个节点都带 `extras.anchor` 与 `illustration: true`。

后果：标签锚点无法从 GLB 读取，只能继续以 `mobile/assets/evolution/car.json` 的 `anchor` 为准。两种处置：

1. **保持 `car.json` 为锚点唯一来源**，按 `Node.name` 与 `component.id` 关联（推荐，改动最小）。
2. 从各 Mesh 的世界包围盒中心推导锚点（几何自洽，但会改变现有原型已调好的标签位置）。

风险：`prototypes/assets/universal-car.glb` 与 `mobile/assets/evolution/car.json` 当前由同一个 `prototypes/build-car-asset.mjs` 生成，源数据一致；但任一生成产物被单独手改或生成后未提交时仍可能漂移。建议增加一处跨产物一致性校验（见第 6 节）。

## 5. 增量迁移方案

遵守规范的现有实现保护要求与「禁止 Hack」原则：采用可回退的增量迁移，不删除已验证交互，不发明能力。

### Phase A：骨架接入（不改视觉，可回退）

1. `pubspec.yaml` 固定 `flutter_scene: 0.23.0`；运行 `dart run flutter_scene:init` 建立资产管线（`hook/build.dart` + `flutter_scene_generated/`）。
2. 将 `universal-car.glb` 纳入受版本控制的源资产并接入构建期预转换（`.fsceneb`），优先于运行时 `Node.fromGlbAsset`。
3. 新增 `GltfCarViewer`，与现有 `CarViewer` **并存**，通过开关选择；默认仍走旧渲染器。
4. 13 个 Mesh 按 `Node.name` 与 `car.json` 的 `component.id` 建立映射，启动时校验 13 项全覆盖，缺失即显式失败（不静默降级）。

产出：能显示 GLB，但交互与标签尚未接管。此阶段结束即可在真机/浏览器目视验收模型正确性。

### Phase B：接管交互（保参数不变）

5. 复用现有手势层参数：`_yaw/_pitch/_zoom` 语义、`0.01×speed`、0.5–3 倍缩放、4px 拖动阈值、前/侧/顶/后预设。**只把相机计算接到 `PerspectiveCamera`，不改阈值**。
6. 点击选中改为 `screenPointToRay` + `Scene.raycast`，替换现有 `partAt` 面命中判定。
7. 选择高亮与其余部件去强调改为逐 `Node` 材质覆盖。
8. 现有 `mobile/test/car_viewer_test.dart` 中关于手势增量与缩放的断言（`closeTo(before + .2)` 等）**必须保持通过且不得放宽**——它们是「手感未被重新设计」的机器证据。

### Phase C：标签与详情

9. 动态技术标注：锚点（来自 `car.json`）→ 世界坐标 → 屏幕投影 → 可用区域排布，旋转缩放后重算，防重叠、少交叉、避让车身。
10. 保留 13 项 `review: pending` 标注与「静态草稿待人工审核」提示，**不得**因迁移而呈现为已审核知识。
11. 屏幕阅读器语义沿用包内语义支持，并复核不低于现有效果。

### Phase D：解除被阻塞的 Phase 2/3 能力

12. Exploded / Assemble（规范 Phase 2 #11）。
13. Focus 保留空间关系（规范 Phase 2 #10）——注意原型报告 L13 已移除旧版「隐藏其余赛车」的 Focus，新实现须是降不透明度而非隐藏。
14. Technical / Livery 模式（#12）、升级→3D 高亮（#14）。
15. Phase 3 的 Ghost Compare 在真深度缓冲下才可做（#17）。

### 现渲染器的去向

`CarPainter` 在 Phase C 完成前保留为回退路径。是否删除应由真机验收结果决定，**不在本方案内预设**。

## 6. 建议新增的一致性校验

针对 4.3 的漂移风险，建议在 `mobile/test/` 增加一项测试：断言 `car.json` 的 13 个 `component.id` 与 GLB 的 13 个节点名集合完全相等，且锚点与 GLB 内 `extras.anchor` 一致。这样「13 个稳定 Component ID 在 schema / car.json / GLB / Flutter 四处不漂移」从人工核对变成机器约束。

现有 `car_viewer_test.dart` 已断言 `components.length == 13`、`materials.length == 5`、900 个面，可作为该测试的基础。

## 7. 本方案不做的事（按「禁止 Hack」）

- 不把 `extras.anchor` 的缺失用「猜一个锚点」掩盖过去。
- 不用 `model_viewer_plus` 一类 WebView 方案替代：它无法提供 13 个 Mesh 的逐部件选中与高亮，属于降级捷径。
- 不在同一提交内既换渲染器又改视觉规格；两者必须可分别回退。
- 不声称跨代模型切换、真实车队规格或已审核技术知识已完成——这些仍是 `docs/evolution.md` 记录的未完成项。
- 不宣称性能达标：原型报告 L49 的 2.92ms 是同机无窗口 Edge 的桌面绘制测量，**不是真机帧率保证**，迁移后需重新测量。

## 8. 需要人工完成的验收（我无法替代）

本机有 AVD `F1Reminder_API35` 与 Android SDK，但以下必须由人在真机上确认：

1. **Android 真机 / 模拟器 Flutter GPU 是否正常渲染**（加 Manifest 开关后）。这是 Flutter GPU 而非普通 Flutter 路径，未经验证不得假定可用。
2. iOS 真机渲染（需 macOS/Xcode，本机无法构建）。
3. 真机手势与帧率，覆盖规范要求的「细化轮胎/车身形状、真机手势和帧率验收仍需后续验证」。
4. 第三方 GLB 兼容性（原型报告 L55 列为未测）。
5. 屏幕阅读器实际朗读效果。

## 9. 未决问题

1. **Android/iOS 是否接受启用 Flutter GPU。** 若不接受，本方案在移动端不成立，需回退到「Web 用 glTF + 原生继续面排序」的分裂状态，或改为自研软件光栅器（成本更高）。
2. **锚点唯一来源**取 `car.json`（推荐）还是从几何推导（第 4.3 节）。
3. **是否同时接入 `dart run flutter_scene:init` 的资产管线**，还是先用运行时 `Node.fromGlbAsset` 降低首次改动面。管线性能更好但改动更大。
4. `docs/evolution.md` 的旧实现描述已在 2026-09-21 更新；后续迁移时继续同步维护实际渲染路径。

## 10. 参考

- [flutter_scene 0.23.0（pub.dev API）](https://pub.dev/api/packages/flutter_scene)
- [flutter_scene 仓库](https://github.com/bdero/flutter_scene)
- [Scene 官方文档](https://fscene.dev)
- 包内自带 agent skills：`skills/{traps,performance,architecture,looks,procedural,loop}.md`，可用 `dart run flutter_scene:skills` 安装
- 本仓库：`docs/evolution-prototype-phase1.md`、`EVOLUTION设计规范.txt`、`docs/evolution.md`
