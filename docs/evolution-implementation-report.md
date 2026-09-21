# Evolution 实现报告

更新时间：2026-09-21

当前实现以轻量、可交互和来源可信为优先。可由现有代码和可靠数据支持的 Phase 1、Phase 2、Phase 3 主流程已经落地；需要人工专业判断或独立几何资产的能力保持显式待完成状态。

## 1. 修改文件

主要实现文件如下：

- 原型与资产生成：`prototypes/car-viewer.html`、`prototypes/build-car-asset.mjs`、`prototypes/car-viewer.test.mjs`
- Flutter 资产：`mobile/assets/evolution/car.json`、`mobile/assets/evolution/universal-car.glb`
- Flutter 构建：`mobile/hook/build.dart`、`mobile/flutter_scene_generated/.gitignore`、`mobile/pubspec.yaml`、`mobile/pubspec.lock`
- Flutter 模型与界面：`mobile/lib/features/evolution/car_model.dart`、`gltf_car_stage.dart`、`car_viewer.dart`、`compare_panel.dart`、`evolution_page.dart`
- Flutter 数据接入：`mobile/lib/data/race_repository.dart`
- Backend：`backend/app/evolution.py`、`backend/tests/test_evolution.py`
- 测试：`mobile/test/evolution_test.dart`
- 文档：`docs/evolution.md`、`docs/evolution-prototype-phase1.md`、`docs/evolution-gltf-migration-assessment.md`、本文

## 2. 复用的现有代码

- 保留原型已经确认的拖拽旋转增量、俯仰限制、缩放比例、预设视角、Reset、键盘操作和点击阈值，没有重新设计 Rotation Interaction。
- 复用现有 Flutter Design System、导航、语言切换、`RaceRepository`、离线缓存和 API Base URL 配置。
- 复用现有 `Team → CarModel → CarSpecification → Upgrade` 数据语义；Generation 作为 CarModel 的产品层概念，没有增加重复实体。
- Reminder、Calendar、Home 的业务代码和接口契约没有因 Evolution 重构。

## 3. 3D 模型资产结构

`universal-car.glb` 是 164,604 bytes 的低多边形 GLB，含 13 个独立命名 Mesh、约 2,140 个三角形。结构覆盖翼面、鼻锥、悬架、轮胎、Halo、座舱、侧箱、底板和发动机盖；不包含动力单元、管线或未经验证的内部结构。

GLB 使用 Flutter Scene 的深度缓冲渲染和射线拾取。Canvas Renderer 读取 `car.json` 中的同源面数据，仅作为设备不支持 Flutter Scene 时的兼容降级。两条路径使用相同 Component ID、Anchor、材质和交互状态。

## 4. Component ID

```text
front_wing
nose
front_suspension
front_wheels
halo
cockpit
sidepods
floor
engine_cover
rear_suspension
rear_wheels
beam_wing
rear_wing
```

这些 ID 同时服务于 Highlight、Focus、Exploded View、Component Detail、Upgrade、Generation Compare 和 Specification Compare。

## 5. Team Material / Livery

`car.json` 的 `materials` 以 team key 保存 `body`、`secondary`、`carbon`、`accent` 四类颜色。目前包含 neutral、Ferrari、McLaren、Mercedes、Red Bull 风格方案。轮胎和轮毂使用共享中性色。

Livery 模式读取当前车队 palette；Technical 模式切换 neutral palette，并调整 metallic/roughness。模型几何不因配色复制，也不包含 Sponsor Logo 或声称为官方完整涂装。

## 6. Generation / Specification 映射

- `carModels[]` 保存 `car_model_id`、team、name、season、`official_url`、`previous_car_model_id`、`base_3d_model_id` 和经过来源约束的 `compare_changes`。
- Generation Rail 和 Heritage 读取同一车型列表；代际对比通过 `previous_car_model_id` 建立前后关系。
- Backend Upgrade 返回稳定 `component_id`、比赛、轮次、变化、目标、预期效果、状态和来源；时间线按比赛轮次生成。
- 点击时间线或规格事件时，`component_id` 传入 Car Explorer，自动选择并 Focus 对应 Mesh。
- 当前 `base_3d_model_id` 均为空，因此所有车型使用通用技术示意几何。未来只需为经过验证的替换组件/底模登记资产 ID，不需要复制交互系统。

## 7. Exploded View

每个 Component ID 对应一个确定的三轴分离向量。`AnimationController` 在紧凑时长内将 exploded 值从 0 插值到 1；Flutter Scene 更新各 Mesh 的 position，Canvas 降级路径在投影前应用相同偏移。Assemble 反向播放动画恢复原位。

爆炸状态继续保留射线点击、标签、部件详情和 Focus。实现仅展示已建模的外部主要部件，不创造机械内部结构。

## 8. Label Projection / Collision Avoidance

每个部件有与 Mesh 坐标一致的 3D Anchor。当前相机旋转、缩放、Focus 或 Exploded 状态变化时，Anchor 重新投影到屏幕坐标。

标签按投影点位于屏幕左/右分组，再按垂直位置排序并施加最小间距；连接线在文字白底之前绘制，避免穿过文字。视口较小时减少非重要标签数量，选中部件优先；屏外 Anchor 不显示。该策略显著减少重叠和跨车连线，但不承诺所有极端角度下的全局最优路径。

## 9. 真实数据与示意数据

真实或具备来源约束的数据：

- RB19、RB20、RB21 的车型名称、赛季、官方车型 URL。
- RB20/RB21 当前展示的官方页面明确提及的部件变化文本。
- Backend 中具备有效 HTTP(S) 来源、原文和生命周期状态的 Upgrade 数据。
- Calendar 生成的比赛顺序，以及由真实 Upgrade 映射出的时间线高亮。

技术示意或待审核内容：

- Universal F1 几何和车队风格配色是 Technical Illustration，不是具体车型 CAD 或完整官方 Livery。
- 13 项部件说明是本地静态知识草稿，`review` 仍为 `pending`，UI 明确显示待人工审核。
- 当前没有已验证的代际独立几何或赛季规格替换组件。
- 空生产升级档案保持空状态，不用 AI 补齐缺失事实。

## 10. Phase 2 / Phase 3 状态

Phase 2 已实现：保留整车空间关系的 Focus、Exploded/Assemble、Technical/Livery、赛季时间线、Upgrade 到 3D Component Highlight。

Phase 3 已实现：Generation Compare、Specification Compare、Heritage，以及按部件查看来源约束的变化描述。

Phase 3 有条件待启用：Ghost Compare。界面和资格判断已经实现；只有前后车型具有两个不同且经过验证的 `base_3d_model_id` 时才启用叠加。当前数据不满足条件，因此显示原因说明。

Later / Optional 未实现：Scan Effect、Layer Peel、Conceptual Aero Flow、X-Ray。它们不影响当前核心体验；X-Ray 将等待可靠内部模型。

## 11. 性能措施

- 单个 164 KB、约 2,140 triangles 的 GLB，无纹理和 Sponsor 图片。
- 进入 Evolution 后才加载模型；不同时加载整个历史车型库。
- Flutter Scene 资源由 `ResourceGroup` 管理，Widget dispose 时移除 Scene Node 并释放资产资源。
- Compare 默认是数据对比；只有具备独立资产时才加载比较几何。
- 动画只在 Focus 与 Exploded 状态切换时运行，无自动旋转、粒子、实时物理或复杂 Shader。
- Canvas 降级只在属性或交互变化时重绘，并保留面缓存和有限标签数。

## 12. 手动测试

1. **Rotate**：进入 Evolution，在模型上水平/垂直拖动；再用 Front、Side、Top、Rear 和 Reset，确认过渡短且可预测。
2. **Zoom**：双指缩放；桌面调试时使用滚轮，确认缩放边界生效。
3. **Component Select**：点击 Front Wing、轮胎、Halo 等 Mesh，再从部件下拉选择；确认高亮、轻微 Focus 与详情同步。
4. **Label**：保持标签开启，旋转、缩放、爆炸；确认标签跟随 Anchor，小屏自动减少，选中部件优先且无明显重叠。
5. **Generation Switch**：选择 Red Bull 后切换 RB19、RB20、RB21；确认车型身份和 Official Car 更新，同时明确使用技术示意几何。
6. **Official Car**：在上述车型点击 `Official Car ↗`，确认由系统浏览器打开对应官方页面；无可靠 URL 的车型不显示入口。
7. **Exploded View**：点击 Deconstruct，确认 13 个主要部件平滑分离且仍可选择；点击 Assemble 恢复。
8. **Evolution**：选择赛季、车队和大奖赛；点击有升级的时间线事件，确认详情和对应 3D 部件高亮。无升级的比赛保持 neutral tick。
9. **Compare**：在 RB20/RB21 打开 Compare 并按部件选择变化；开启 Specification Compare 检查前后规格数据。确认 Ghost Compare 在缺少独立几何时保持禁用并说明条件。

自动验证命令：

```text
cd mobile
flutter analyze
flutter test
flutter build apk --debug

cd backend
python -m unittest discover -s tests
```

HTML 原型可额外执行：

```text
node prototypes/car-viewer.test.mjs
```

## 验收结论

当前代码完成了可由现有资产和可信数据支持的 Evolution 交互闭环。正式宣告内容层完整仍需要两项外部输入：13 项基础知识的人工技术审核，以及至少两套经过验证的代际/规格几何资产。现有架构已经为两项输入保留直接映射位置，无需通过 Hack 或大范围重构补齐。
