# Evolution HTML · Phase 1 第一批

本次按 `EVOLUTION设计规范.txt` 继续独立 HTML 调试。Flutter、Backend、Reminder、Calendar、数据库和服务器均未修改。第一阶段尚未全部完成：真实世代差异几何和人工知识审核仍待完成。

## 文件与复用

- `prototypes/car-viewer.html`：离线界面、可编辑几何、材质、静态说明和交互。
- `prototypes/build-car-asset.mjs`：从 HTML 唯一几何源生成 GLB，无 npm 依赖。
- `prototypes/assets/universal-car.glb`：生成资产，13 个独立命名 Mesh，2,140 个三角形，164,604 bytes。
- `prototypes/car-viewer.test.mjs`：本机 Edge 自动交互、响应式及资产结构回归。
- 本文及 `docs/evolution.md`：进度与验收边界。

复用原来的正交投影、拖动增量、角度范围、滚轮曲线、双指缩放比例、点击判定、视角预设、参数导出和键盘操作。保持 `0.01 × speed` 的旋转灵敏度、0.5–3 倍缩放、4px 拖动阈值。移除旧版隐藏其余赛车的 Focus，等待 Phase 2 实现保留空间关系的方案。

## 模型与材质

同一底模使用截面放样车身、分段圆形轮胎、连杆悬架、管状 Halo、开放座舱和多层翼面。没有内部动力单元。几何是技术示意，不是 CAD，不声称符合某个车队、年代或技术规则尺寸。

稳定 Mesh ID：

```text
front_wing       nose              front_suspension
front_wheels     halo              cockpit
sidepods         floor             engine_cover
rear_suspension  rear_wheels       beam_wing
rear_wing
```

GLB 的每个节点保留 `extras.anchor` 和 `illustration: true`。配色由 `materials[team]` 的 body、secondary、carbon、accent 定义，轮胎和轮毂共享中性色；secondary 已预留但当前几何尚未使用。提供通用、Ferrari、McLaren、Mercedes、Red Bull 风格配色，不复制几何，不使用品牌 Logo，不声称完整官方涂装。选中部件红色高亮，其余部件轻度去强调。

HTML 为保持双击离线运行，直接绘制同一几何源；GLB 是可交付资产，尚未接入 Flutter，也尚未通过第三方 GLB 查看器验收。重新生成：`node prototypes/build-car-asset.mjs`。

## 数据边界与后续映射

当前车型选择器只有通用示意和 Ferrari SF-23 档案示例。SF-23 的 2023 年车型身份及链接来自 [Ferrari 官方车型页](https://www.ferrari.com/en-US/formula1/sf-23)；网页可能显示反爬验证。未下载参考图片。

`prototype_ferrari_sf23` 是隔离的原型记录 ID，不是生产数据库 ID。该记录的 `base_3d_model_id` 为 null；选择它会明确提示专属几何尚未提供，下方仍是通用示意，而非切换到所谓 SF-23 模型。其余车队没有已核验车型数据时只提供配色，不显示 Official Car。

未来使用现有 `TeamSeason → CarModel → CarSpecification`；Generation 是 CarModel 的产品概念，不新增同义实体。`Component3DMapping` 将数据库部件 ID 映射到上述 Mesh 和 Anchor。经过来源审核的替换组件才能由 Specification 配置加载。目前没有车型差异、比赛规格、升级事件或性能结论的假数据。

13 项说明是本地静态草稿，界面明确显示“待人工审核”，不调用 LLM。尚不能作为已审核知识库发布。

## 标签和渲染

Anchor 使用与模型相同的投影。标签按锚点所在左右半屏分组、按高度排序、约束垂直间距；文字覆盖白底避免连线穿过文字。桌面最多 6 个，小屏最多 3 个，选中部件优先。屏外锚点不显示标签，部件下拉仍可选择。连线交叉并非在所有极端视角下完全消除。

本次继续使用 Canvas 面深度排序；存在复杂遮挡排序和透明叠加限制，不作为 Ghost Compare 的最终渲染器。进入透明、爆炸、对比阶段前应采用带深度缓冲的 glTF 渲染器，并保留现有输入控制参数，不能靠增加面排序补丁代替深度测试。

性能措施：单模型、无贴图、无外部请求、无连续动画循环、交互时才重绘、DPR 上限 2。约 900 个绘制面。当前机器无窗口 Edge 连续 60 次 draw 平均约 2.92ms；这是桌面绘制测量，不是真机帧率保证。

## 验证

执行 `node prototypes/car-viewer.test.mjs`：通过。需要 Windows Edge；可通过 `EDGE_PATH` 指定路径。测试输出和专用浏览器 Profile 位于忽略目录 `.tools/evolution-preview/`，不提交。

覆盖几何有限值、13 个 Mesh、GLB 头和命名、拖拽角度增量、滚轮与双指比例、实际可见面点击、13 项详情、配色切换、官方链接显示条件，以及 1440、390、320、844px 视口无横向溢出、标签不重叠、无 JS 异常。已人工查看桌面和手机截图。未测试 Android 实机、屏幕阅读器、GLB 第三方渲染兼容性。

手动双击 `prototypes/car-viewer.html`：

1. Rotate：拖动或方向键；用原参数与上一版比较手感，再试前/侧/顶/后及重置。
2. Zoom：滚轮、双指或缩放滑块；达到上下限后不能越界。
3. Component Select：点击轮胎、Halo、翼面或从下拉选择；确认高亮、ID 和三个说明段落一致。
4. Label：旋转缩放，观察标签跟随；小屏减少数量，开关可隐藏。
5. Generation Switch：Ferrari → SF-23 档案，确认显示“几何待建模”，不声称切换真实模型；返回通用条目。
6. Official Car：仅 SF-23 档案显示，打开官方页；其他配色不显示不可靠链接。
7. Exploded View / Evolution / Compare：本批没有这些入口，不以空按钮冒充完成。

## 剩余工作

Phase 1：确认模型轮廓、选择代表车型并依据可靠来源制作可替换差异组件、扩充经过核验的车队车型档案、人工审核部件知识、GLB 渲染兼容性和真机性能验收。现阶段不应宣称跨代模型切换完成。

Phase 2：有上下文的 Focus、平滑 Exploded/Assemble、Technical/Livery 模式、已有升级 API 与部件映射、赛季时间线和升级高亮。爆炸位移与动画本批尚未实现。

Phase 3：Generation/Specification Compare、可靠透明叠加条件下的 Ghost、Heritage。Scan、Peel、概念气流及有可靠内部模型后的 X-Ray 继续延后。
