# GrandPrixReminder UI v2 — Visual Specification & Gap Audit

状态：用户已确认并授权实施。以下保留原始差异审计；实现记录见 `docs/ui-v2-implementation.md`。日期：2026-09-24。

## 1. 唯一视觉基准与审计范围

唯一 visual source of truth 为用户提供的 `E:/Downloads/ChatGPT Image 2026年9月24日 12_49_28.png`（1536 × 1024，四个手机画面）。直接通过会话原生视觉读取。图外的 HOME / BRIEFING / EVOLUTION / 3D EXPLORER 说明、手机外壳、系统时间和灵动岛不属于应用内容。

目标是在 Flutter 能力与真实数据、资产边界内尽可能 1:1 复刻布局、信息层级、字体关系、间距、分隔线、色彩、导航和 3D 区域比例。其他设计模板不能替代此图。截图内的 Azerbaijan、Spain、Norris、日期、积分、Cadillac 升级描述及数量均为视觉示例，不构成赛事证据或待录入事实。

本审计基于当前工作树源码、资源和后端约束，并非运行中的逐像素比较，也未验证生产数据当前可用性。数值为参考图人工估值，实施时以相同视口截图叠加校准；不能声称已识别原始字体或精确色值。

已检查：`mobile/lib/app.dart`、`core/theme.dart`、Home、Briefing、`shared/race_briefing_view.dart`、Race Detail、Evolution、CarViewer、GLTF stage、Compare Panel、RaceRepository、`mobile/assets`、`pubspec.yaml`、`backend/app/briefing_worker.py`、`backend/app/evolution.py`、Evolution evidence/review 流程及 `docs/evolution.md`。已有未提交修改：`mobile/lib/app.dart`、`mobile/test/app_test.dart`；本次保留原状。

## 2. 核心视觉判断

参考图是黑底的赛车编辑式界面：高对比衬线大标题、紧凑无衬线元数据、少量赛车红、满宽摄影/模型舞台、编号列表与细横线。主要层级来自字号、留白和图文比例，而非卡片容器。

现有主题已经具有深色背景、低圆角、细 divider、无导航胶囊底色；不能笼统描述为全部 Card-heavy。主要差异是默认无衬线标题、统一 AppBar 与页面内边距、大量纵向控件、缺少摄影主视觉，以及 Explorer 未形成独立部件详情页。

匹配优先级：页面骨架与区域比例 → 字体与信息密度 → 舞台与图片裁切 → 行间距/divider → 图标细节。证据真实性、业务可达性、无障碍及本地化优先于把内容强行塞入截图高度。

## 3. 逐项差异审计

Existing 指源码已有能力；Missing Feature 指缺失或部分缺失，不等于后端全无；Backend Dependency 与 Asset Dependency 分别列出真实链路和素材前提。“无新增”表示可复用，不代表可以绕过现有接口。

### 3.1 全局与导航

| 项目 | Existing | Visual Change | Missing Feature | Backend Dependency | Asset Dependency |
|---|---|---|---|---|---|
| 页面框架 | 固定品牌 AppBar、24dp 页边距、最大宽760、全页滚动 | 页面级 editorial header；照片/舞台可满宽，文字独立缩进 | 共享 editorial shell | 无新增 | 无 |
| Typography | 默认系统无衬线，display 38/700 | 高对比衬线标题与序号，窄而清晰的无衬线正文 | 品牌字体角色与中文回退 | 无 | 授权字体文件；当前 pubspec 未注册字体 |
| 底部导航 | Home / Races / Briefing / Evolution；Settings 在顶栏 | Home / Calendar / Explore / Settings；红色选中图标与文字、顶部分隔线 | 新入口映射与栈内状态恢复 | 复用原业务状态与服务 | 统一线性图标；品牌标记需合法资源 |
| 分享 | 目标页面未见对应分享操作 | Briefing/Evolution 右上细线分享图标 | 系统分享及失败处理 | 使用真实赛事与来源链接；应用深链若新增需完整处理 | 无 |
| 状态与设置 | loading/error/retry/stale、语言、Spoiler-Free、Follow 已有 | 同一背景上的文字状态、细分隔线；保留可操作反馈 | 新组件中的一致状态覆盖 | 保留缓存、lang、刷新行为 | 无 |

### 3.2 Home

| 项目 | Existing | Visual Change | Missing Feature | Backend Dependency | Asset Dependency |
|---|---|---|---|---|---|
| 主视觉 | 赛事名、赛道、开始时间、生命周期文字 | 顶部品牌/赛季；轮次眉题；巨大两行赛事名；赛道与轮廓；日期；全宽摄影 | 赛事摄影映射、日期区间与轮次展示 | next-race + season schedule；Race 当前无显式 round，应补可选字段或由完整有序赛历核实推导 | 赛事关联且授权的场景/赛车照片；现有赛道 SVG 可复用 |
| 倒计时 | 实时时间差，赛周 current/next session | 红色衬线三列 DAYS/HOURS/MINUTES，细竖线 | 仅呈现方式缺失 | 复用真实时刻与 lifecycle；不得固定截图数字 | 字体 |
| Weekend Schedule | session 列表、当地时间与状态 | 日/日期/时间/场次紧凑行表、细 divider、LOCAL TIME | 紧凑表格组件 | 现有 sessions；Sprint 等全部保留，未知时间明确显示 | 无 |
| Latest | Home 无该聚合区；其他页面已有 Briefing/Evolution | 红色栏标题/短下划线、赛事眉题、两条可点击记录、View all | 最新内容聚合与可用性判断、历史列表入口 | 完成赛事列表 + briefing + evolutionRace；可先复用接口，按需新增兼容聚合，避免逐赛请求风暴 | 文章/扳手图标 |
| Reminders / Follow / Source | 已直接存在 Home 或详情 | 日程后紧凑操作区；完整设置进入详情；来源用共享行 | 无业务缺失，仅位置调整 | 保留权限、持久化、stale 调度保护与关注上下文 | 无 |

### 3.3 Briefing

| 项目 | Existing | Visual Change | Missing Feature | Backend Dependency | Asset Dependency |
|---|---|---|---|---|---|
| Header | 标题、已完赛赛事下拉、赛事名 | 返回/分享；轮次；BRIEFING 大标题与衬线副标题；摄影人物靠右 | 摄影 header、紧凑赛事切换 | 已完赛选择逻辑继续使用；不得固定 Spanish GP | 经授权、匹配赛事的报道照片 |
| Key Stories | insight.topic/detail/sources，Follow 排序 | 01…序号、红色主题、实体眉题、短摘要、右侧缩略图/箭头，细线分隔 | 条目详情与字段映射；当前 insight 无独立实体/媒体/类别字段 | 复用来源支持的 insights；实体或类别需要可靠结构字段，不从标题猜测 | 对应车手/赛车/轮胎图片与归属 |
| Race Result | Race Detail 已有正赛/排位、最快圈等 | 放入 editorial tab，保留完整结果入口 | Briefing 内承载视图 | 复用 results/qualifying；不只留下冠军一行 | 无必需图片 |
| Quotes | worker 有 key_quotes 和 evidence 存储；移动端仅通用 insight | 独立 tab，原话、说话人、出处 | 结构化引语呈现与原文关联尚不完整 | 从已验证引文输出 speaker、text、source/anchor；无法确认说话人或原文时隐藏或 Unknown | 可选授权头像 |
| Analysis | Race Detail 已有 story、strategy、championship-impact | 独立 tab/编号章节；分析与数据区分 | 跨现有数据的编辑呈现；证据支持的分析字段 | 复用各真实接口；轮胎 stint 不能自动证明“退化超预期”，积分不能证明主观因果 | 可选对应图片 |
| Source / Spoiler-Free | 整体 spoiler gate、来源抽屉、缓存警示 | 每条详情可追溯，统一来源行 | 新 header、图片、摘要、tab 都受 gate 约束 | 复用 sources、stale、updatedAt；新增字段仍须证据链 | 摄影也须防剧透分类 |

### 3.4 Evolution

| 项目 | Existing | Visual Change | Missing Feature | Backend Dependency | Asset Dependency |
|---|---|---|---|---|---|
| Header/上下文 | 标题、赛季与车队筛选 | 比赛眉题、大标题、副标题、真实 documented updates 计数；筛选折入紧凑入口 | 比赛概览布局 | evolutionRace / season feed；计数必须标明当前赛事/筛选范围 | 字体 |
| 3D 舞台 | GLTF/Canvas、通用车、13部件、旋转缩放点击 | 黑底连续舞台、车体占主要宽度、右上全屏 | 全屏容器与状态往返；高精度外观未具备 | 稳定 team/component/upgrade 身份 | 现有通用几何可复用；图中精细车身/材质需额外授权资产 |
| 视角/模式 | Reset、Front、Side、Top、Rear；Technical/Livery、Focus、Exploded、labels、wire | Front/Side/Top/Rear 细文字 tab；Standard/Technical 红线切换 | 共享控件布局 | 无新增；Standard 对应现有 Livery | 无 |
| 更新列表 | 按车队筛选的 ExpansionTile；change/goal/effect/status/sources | 编号行、部件名、车队/状态、摘要、部件缩略图、详情箭头 | 赛事跨车队概览、部件详情路由和同步选中 | feed 已可提供多车队记录；保留原车队筛选，计数随范围一致 | 实际模型部件截图或来源支持的技术图 |
| Timeline/lifecycle/比较 | 赛季时间线、所有比赛、规格/代际比较、Heritage、Follow | 不占满首屏：舞台工具与后续 editorial section | 无业务删除；需重新安置入口 | 原 lifecycle/status 与赛季数据 | 保留既有车型与来源记录 |

### 3.5 3D Explorer

| 项目 | Existing | Visual Change | Missing Feature | Backend Dependency | Asset Dependency |
|---|---|---|---|---|---|
| 独立详情 | CarViewer 嵌在 Evolution，部件点击打开 timeline bottom sheet | 返回；FLOOR/车队/赛事；大部件特写；缩略图带；详情正文 | 独立部件 Explorer 页面与选中状态往返 | 通过 upgradeId/raceId/teamId/componentId 关联原数据 | 同源模型部件与相机预设 |
| 部件特写/缩略图 | Focus 与部件选择存在 | 部件占舞台、红色细轮廓选中、三张实内容缩略图 | 缩略图生成/选择、详情舞台构图 | 缩略图选择切换实际部件或视角，并更新语义标签 | 真实渲染捕获；不能拿静图冒充可旋转模型 |
| Details / Purpose | change、goal、expectedEffect 已有，基础知识在 car.json | 标签红色、正文浅白、段落之间细线 | 标签映射与缺失状态 | Details ← change；Purpose ← 有证据 goal；expectedEffect 单列保留，不能合并成既成事实 | 无 |
| Confidence | 当前字符串，仅部分低分提示 | 明确值/等级与解释 | 缺失/非法值 Unknown；一致映射 | 使用真实 confidence；既有 <0.75 规则可作 Low，其他等级需明确规则，不臆造校准概率 | 无 |
| Source | provider/url/publishedAt 已有、外链组件可复用 | publisher + 文档标题 + 外链图标 | 文档标题当前 Source DTO 无字段 | 没有 title 不编造“Technical Update”；可加可选字段与 evidence anchor | 无 |
| Ghost Compare | 赛事规格比较可开关并用 Canvas 叠加；代际分支 ghostAvailable=false | 保留对比入口、前后身份和真实条件说明 | 真正赛事几何版本映射尚缺 | 必须区分文字规格差异与几何差异；见第7节 | 可验证的不同几何版本及映射 |

## 4. GrandPrix Design System（拟定，尚未实现）

### 4.1 Token 与排版

以下为约 390dp 宽设备的初始值，最终依参考图校准。参考图手机内内容宽约360像素，不能把整张1536像素当作单页宽度。

| Token/角色 | 初始规格 |
|---|---|
| Background / Surface | #090B0C / #111416，连续暗底；避免大面积分块 |
| Text primary / secondary / muted | #F2F0EB / #C4C7C9 / #8C969D；小字按实际背景检查对比度 |
| Accent / divider | 赛车红 #FF4055；divider #3B4143，0.5–1dp |
| 状态 | introduced 低饱和绿、modified 蓝灰、low confidence 琥珀色；总附文字 |
| Display | 高对比衬线，40–48sp，行高1.0–1.08；Home赛事名允许自然换行 |
| Deck / part title | 衬线22–26sp / 30–34sp |
| 编号 / countdown | 衬线28–32sp / 38–42sp；计时数字等宽 |
| Body / compact summary | 无衬线14–16sp / 12–14sp，行高1.35–1.5 |
| Metadata / nav | 10–12sp / 10–11sp，英文标签适量字距；中文不强行拉开字符 |
| Spacing | 4、8、12、16、20、24、32；正文水平20–24dp；编号栏32–40dp |
| 圆角 / elevation | 主区块0；小缩略图4–6dp；无卡片投影、Glow 或装饰渐变 |
| Active indicator | 红色2–3dp细下划线；缩略图1dp红框 |

字体角色优先高对比 editorial serif + 清晰 condensed sans；原字体无法从截图确定。实施前选择可嵌入且许可明确的字体并校准字宽；中文用匹配衬线/黑体回退，字体资产纳入离线包。不能只给系统字体换颜色就声称字体匹配。

摄影自身明暗与3D材质真实光照属于素材内容。正文应利用照片暗区和裁切保证可读性；避免用大面积渐变、霓虹或发光遮罩弥补构图。选中部件使用清晰细轮廓，按用户要求不复刻图中的红色 Glow。

### 4.2 共享 Editorial components

| 拟定组件 | 责任 |
|---|---|
| GrandPrixPageShell / BottomNav | SafeArea、滚动、边距、导航选中态与返回语义 |
| EditorialHeader / RaceEyebrow | 返回/分享、轮次、赛事、标题、副标题、可选媒体 |
| SectionRule / EditorialTabs | 栏标题、细线、红色激活条；tab 可横向滚动而不截断文字 |
| NumberedEditorialRow | 序号、主题/实体、摘要、可选缩略图、实际详情动作；列表编号随实际排序生成 |
| WeekendSchedule / CountdownStrip | 真实场次与本地时间、三列倒计时 |
| CarStageFrame / ViewControls / ComponentStrip | 同一模型状态、视角、模式、全屏、缩略图；不重写渲染器 |
| EvidenceField / SourceRow / ConfidenceLabel | Unknown/隐藏规则、来源链接及失败反馈、置信度语义 |
| EditorialContentState | loading、empty、error/retry、stale、spoiler、模型降级；不伪装为已加载内容 |

这些是复用责任边界，不要求每个名字单独建立文件，也不引入通用页面生成框架。

## 5. 页面比例与信息架构

以去除设备外壳后的约390 × 930dp画布作为首轮校准基线，状态栏、安全区按实际设备取得。

| 页面 | 参考布局与首屏比例 |
|---|---|
| Home | 顶部品牌约40dp；眉题/赛事/日期与摄影共约390–430dp；计时约70dp；Schedule约165–180dp；Latest两行；底部导航约64dp + bottom inset |
| Briefing | 返回栏约40dp；摄影与标题共同组成约260–290dp hero；tab约44dp；编号列表每行约125–140dp；底栏固定 |
| Evolution | 返回栏+标题区约190–215dp；模型舞台约180–220dp；视角与模式各约44dp；编号更新行约110–125dp；底栏固定 |
| Explorer | 返回/部件标题区约140–155dp；特写约220–250dp；缩略图约60–70dp；Details/Purpose/Confidence/Source逐段展开；截图中无底栏，采用沉浸子页面 |

这些高度为构图目标而非内容硬限制。正文长、中文、200%字级、更多场次时向下滚动；不得裁掉来源、以省略号替代唯一事实或限制只能展示3条更新/4条新闻。

导航映射：Home 的 Latest → 指定赛事 Briefing 或 Evolution；Calendar 复用原 Races 与全部历史/详情能力；Explore → Evolution，点击更新 → 部件 Explorer；Settings 保留全部设置。Briefing 历史选择在 Header 和 Latest 的 View all 可达；View all 打开实际完成赛事/内容列表。截图中 Briefing 保持 Home 选中；Evolution 保持 Explore 选中。

图中未显示的能力安置：Reset 作为第五视角控制；Focus、Exploded/Assemble、labels、wire、旋转与缩放按钮进入舞台工具栏；Timeline、Specification Compare、Generation Compare、Heritage 放在舞台后续分区及可见工具入口。不得仅保留隐藏状态或移除调用路径。从全屏/Explorer 返回保留赛事、车队、部件、相机、模式与滚动上下文。

## 6. 新功能真实数据链路

| 功能 | 链路与验收 |
|---|---|
| Home Latest | 完整赛历确定真实已完成赛事 → 查询内容可用性 → 返回真实 Briefing/升级数量 → 按raceId跳转。空数据显示无已发布内容；不以赛事结束推断 Briefing 已发布。需要聚合时新增兼容接口，不修改旧端点语义。 |
| 轮次/日期区间 | 后端赛历轮次与赛季总轮数 → 可选DTO字段；跨取消赛事的统计口径明确。日期区间取赛程且与显示时区一致；字段缺失不硬写12/23或20–22 SEP。 |
| 媒体 | 许可明确的图片/模型 → 带来源、版权、race/team/entity关联和版本的资产记录 → 客户端准确绑定与裁切。当前无此通用链路，需实现；缺失时使用真实无图布局并记录视觉未达标，不能放随机照片。 |
| Quotes | 原始来源 → worker支持的key_quotes/evidence → 引语身份/原文可核验的输出 → Quotes视图 → 原文来源。现有通用insight不能当成可随意拼接的直接引语。 |
| Analysis | 已发布且有来源的分析字段，或有明确计算口径的数据指标 → 视图。事实摘要与推测分开；没有证据的因果、Purpose或Analysis隐藏/Unknown。 |
| Explorer | 点击真实升级 → 稳定ID读取同一记录 → 可映射部件聚焦 → change/goal/effect/status/confidence/sources → 原始出处；不支持映射时保留文字详情并说明。 |
| 分享 | 用户点击 → 系统分享真实标题、赛事标识与来源URL；支持应用链接时必须能解析并恢复上下文。取消不报错，失败可重试；不能输出虚构深链。 |

API扩展仅允许向后兼容的可选字段或新增接口。当前 `/api/v1/next-race`、`races`、`results`、`qualifying`、`story`、`strategy`、`championship-impact`、`briefing`、`evolution`、`roster` 的路径、字段语义、语言和缓存行为保持兼容。不得为UI重构改动生产数据或触发发布worker。

## 7. Evidence 与3D真实性边界

1. Briefing worker 会检查 evidence quote 是否出现在来源文本中；Evolution 输出依赖 published 升级、已发布claim、accepted关联及来源。新增内容继续通过既有审核链，不从截图抽取事实写入数据库。
2. 有来源URL不等于每个新字段都有证据。新增Purpose、Analysis、Quote需要字段级支持；后端若暂未暴露字段级anchor，可保持现有来源追溯并明确升级依赖，不能伪称已支持逐句定位。
3. `goal`可映射Purpose，`expectedEffect`保持预期效果，`change`保持记录的变化；无证据时Unknown或隐藏。官方发布者不自动等于高置信度。
4. 基础部件知识、静态草稿、赛事实际升级三者必须区分。`car.json`中的pending review知识不能被升级详情包装为已证实事实；保留草稿提示。
5. 通用赛车仍明确标记Technical Illustration / Generic model。队色、车型名字和来源链接不使其成为真实车队CAD或对应赛事规格。
6. 已发现文档/代码差异：`docs/evolution.md`描述Ghost需要两个验证过的不同base_3d_model_id；`evolution_page.dart`赛事规格分支实际上以“存在前一场 + 有可映射部件”启用，`car_viewer.dart`使用通用Canvas进行叠加；代际比较分支禁用Ghost。不能将现状报告为已具备真实几何比较。
7. 实施需保留Ghost功能入口与比较上下文，区分示意叠加和真实几何比较。真实比较需要前后版本资产、来源、有效赛事/时间与component映射；前提不足说明不可用并保留来源支持的文字比较。不得用同一模型变色、偏移或缩放伪造几何变化。该语义修正列为单独可审查项，不悄然与换肤混合。

## 8. 不回归清单与验收

| 能力 | 必须保持的行为 |
|---|---|
| Reminders | 权限申请、赛前提醒、偏好持久化、赛程刷新、后台/恢复时同步、stale保护；新增Home入口仍调用原service |
| Spoiler-Free | 结果、新闻文本、摄影、缩略图、分享预览与无障碍标签均不提前泄露；按现有session reveal规则恢复 |
| Follow | 车手/车队关注、取消、持久化、列表排序和上下文；不因新的编号排序失效 |
| Localization | 中英/随系统、动态切换、API lang、缓存隔离、当地时间；新文案进入本地化体系 |
| Evolution | 赛季/车队/比赛筛选、全部lifecycle状态、Timeline、13部件映射、Refresh、无映射和无记录状态 |
| 3D | GLTF和Canvas降级、点击/键盘、旋转缩放、Focus、Exploded、Technical/Livery、5 views、labels/wire、规格/代际/Heritage/Ghost入口 |
| Source tracing | Briefing与升级来源、发布日期、外链失败反馈、低置信度/静态草稿、cached/stale标志 |
| Calendar/详情 | 历史赛季、赛事生命周期、赛道图/弯角、正赛/排位、story、strategy、championship-impact和完整结果 |

视觉验收：同尺寸英文常规字级截图对齐四屏，叠加检查左右边距、标题基线、hero/舞台上下界、tab、divider与底栏；主要结构边界初始容差4dp、局部间距2dp，字体光栅与操作系统安全区单独记录。真实数据长度差异不得靠改写事实匹配。

响应式验收：至少360/390/430dp宽、中文与英文、正常/放大字级；点击区域至少44dp；屏幕阅读器有标签；tab与导航不依赖颜色唯一传达；减少动态效果设置继续有效。桌面保持单列阅读宽度与交互可达，不自行发明dashboard。

状态验收：四页覆盖loading/empty/error/retry/stale；媒体缺失、无证据、未知confidence、无3D映射、GLTF失败、无可比版本有真实反馈。每个箭头、tab、缩略图、分享、View all、source、fullscreen都有真实动作；有条件不可用的功能明确原因，不提供无效点击处理器。

实现后验证：运行Flutter analyze与相关既有app、functional integration、race detail、reminder、spoiler、follow、evolution、car viewer、layout测试；有API或字段扩展则运行对应backend schedules/results/post_race/briefing/evolution/localization测试和兼容性检查。针对新入口、防剧透媒体与真实数据缺失补充有意义的测试。本次只有文档，不运行或声称通过代码回归测试。

## 9. 确认后的实施顺序与交付门槛

1. 固定当前业务/接口基线，先构建共享token、shell、editorial组件与导航映射；保留工作区已有修改。
2. Home和Briefing重构，接通Latest、tab与来源；结构化Quotes和媒体链路作为明确功能项处理。
3. Evolution与Explorer分层，复用渲染/交互，接通全屏、部件缩略图、详情和完整工具入口。
4. 完成新增字段/媒体/几何依赖的真实链路与审核；不足项保持显式缺失，不能作为已完成的1:1交付。
5. 逐屏视觉校准、状态/业务回归、API兼容性验证后提供可审查diff。生产发布不属于本次第一步。

当前1:1主要依赖缺口：授权赛事摄影与缩略图、品牌字体、精细车体/部件材质、赛事几何版本，以及Quotes/媒体元数据的可靠输出。布局与共享组件可以在确认后推进，但缺少这些依赖时不能承诺已达到图中摄影及3D保真度。

**以上为已确认的审计基线。实现已推进；摄影与真实赛事几何资产仍是达到1:1视觉验收的前提，详见实现记录。**
