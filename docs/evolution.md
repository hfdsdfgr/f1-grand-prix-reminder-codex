# Evolution 当前状态

Evolution 已按 `EVOLUTION设计规范.txt` 完成可由现有数据支持的 Phase 1、Phase 2 和 Phase 3 主流程。Flutter 页面提供轻量低多边形赛车、稳定部件选择、动态标签、Focus、爆炸/组装、Technical/Livery、赛季升级时间线、代际/规格对比及 Heritage。实现详情和验收边界见 [Evolution 实现报告](evolution-implementation-report.md)。

## 已接通能力

- `mobile/assets/evolution/universal-car.glb` 包含 13 个独立可寻址部件，共用一套 Universal F1 Base。
- Flutter Scene 提供深度渲染和射线点击；不支持该渲染路径时保留同源 Canvas 降级。
- 车队配色由数据中的材质表驱动，不复制模型文件。
- `GET /api/v1/evolution?season=<year>` 返回升级档案和比赛时间线；升级记录通过稳定 `component_id` 驱动 3D 高亮。
- RB19、RB20、RB21 的车型身份、官方链接和文本对比只使用已记录的官方来源结论。
- Generation Compare、Specification Compare 与 Heritage 已接入；Ghost Compare 只在双方具有不同且经过验证的 `base_3d_model_id` 时启用。

## 数据边界

- 通用赛车属于 Technical Illustration，不是具体车型的 CAD 重建。
- 13 项部件说明仍标记为 `review: pending`，完成专家人工审核前保持“静态草稿”提示。
- 当前车型的 `base_3d_model_id` 均为空，因此代际切换复用通用几何；界面不暗示存在真实几何差异。
- Ghost Compare 当前显示前置条件说明，不用同一几何伪造叠加差异。
- 生产升级档案允许为空；升级须具备有效来源与原文证据，并通过独立模型复核后才由 Backend 自动发布。模型复核仍可能误判。

## 后续数据工作

1. 由合适的 F1 技术审核者审核 13 项基础部件知识并更新 review 状态。
2. 根据可靠公开资料制作至少两个具有可观察差异的替换组件资产，登记不同 `base_3d_model_id` 后再启用 Ghost Compare。
3. 持续录入经过来源审核的赛季升级、规格生命周期与车手反馈。

以上工作是内容与资产审核，不需要重写现有 Rotation、Renderer、Reminder 或 Calendar。
