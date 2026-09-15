# GrandPrixReminder

Evolution 已接入赛季升级档案与车队、分站筛选，升级详情显示原始来源。生产升级资料尚待采集审核，空档案明确提示。下一阶段采用交互优先的低精度通用赛车，详见 `docs/evolution.md`。

轻量级 F1 赛事助手。Flutter 客户端只访问自建 FastAPI 服务。

当前框架：四页导航、极简自适应明暗主题、下一场赛事、设备时区、倒计时、赛季赛历、Jolpica 标准化及 SQLite 缓存。赛事详情根据赛前、比赛周末和赛后三种生命周期调整内容优先级；Session 状态由后端统一计算。

关注功能使用设备本地存储；主页和比赛周末会根据 Jolpica 赛季车手积分榜中明确发布的车手—车队归属，展示已关注对象。后端与客户端均保留短期缓存，离线时会标识为已保存数据；不引入账号或云同步。

赛后 Strategy View 使用 FastF1 的已发布逐圈记录显示轮胎配方、stint 圈段、起始胎龄与进站圈，并单独标示数据来源及缓存状态。没有可验证的轮胎记录时保持为空；不推测策略、undercut 或实时遥测。
语言默认简体中文，可通过右上角语言按钮切换 English；选择会在本机保存。日期与系统控件同步本地化。翻译集中在 `mobile/lib/core/language.dart`，未收录的上游赛事和赛道名称保留原文。
赛历条目显示冠军与最快圈并可打开详情，按需查看正赛成绩、排位 Q1/Q2/Q3、积分、发车位和完赛状态。详情页按赛前、比赛周末、赛后三种生命周期显示周末状态；当前已接入 Baku、Marina Bay、Suzuka 的版本化 SVG 赛道轮廓，资源来源和 CC BY 4.0 署名见 `mobile/assets/circuits/ATTRIBUTION.md`。赛季摘要以两次批量请求获取，不按分站产生 N+1 请求；正赛和排位独立缓存，缺失数据明确标记。
首页「赛事提醒」支持 Android/iOS 本地通知：默认开启后续正赛自动提醒，提前 1 小时通知下一场及已公布的后续比赛，首次启动请求系统授权。正赛、排位和冲刺赛也可分别设置提前 24 小时 / 1 小时 / 15 分钟或自定义 1～10080 分钟；支持保存、替换和取消。网页版仅预览设置，不安排通知。
原生通知代码及平台配置已接入，实际送达尚需真机验收，详见 `docs/reminders.md`。最近一次成功的赛历与比赛成绩会写入设备缓存；离线重启时继续显示并明确标记为已保存数据。设置中可开启无剧透模式，跨 Home、Races 和详情页隐藏已结束比赛的结果，用户可逐场揭晓。Briefing / Evolution 仍待开发。

## 启动后端（PowerShell，仓库根目录）

```powershell
py -3.13 -m venv backend/.venv
backend/.venv/Scripts/python -m pip install -r backend/requirements.txt
cd backend
.venv/Scripts/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

接口文档：http://127.0.0.1:8000/docs 。`GET /health` 不依赖外网。
`GET /api/v1/next-race` 获取下一场比赛；`GET /api/v1/races?season=2026` 获取赛历；`GET /api/v1/seasons` 获取可选择的赛季。Race 响应同时包含 `lifecycle_phase`、`current_session`、`next_session` 与 `countdown_target`；比赛进行期间 `next-race` 保持指向当前比赛周末。
赛历默认包含已完赛分站的冠军与最快圈摘要；通知同步使用 `summaries=false`，只读取轻量赛程。
`GET /api/v1/races/{season}-{round}` 获取赛事元数据；其 `/results` 与 `/qualifying` 子路径返回标准化成绩、来源和更新时间。
`GET /api/v1/races/{season}-{round}/schedule-revisions` 返回赛程改期历史；`GET /api/v1/data-health` 返回 Provider、Parser 与 Schema 健康状态。
成绩缓存：当季 15 分钟、历史赛季 24 小时、空结果 5 分钟；赛季摘要当季 15 分钟、历史赛季 30 天。上游故障有缓存时返回 `stale=true`，无缓存时 503。无效 ID 返回 422，不存在的分站返回 404。
字段依据 [Jolpica results](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/results.md) 与 [qualifying](https://github.com/jolpica/jolpica-f1/blob/main/docs/endpoints/qualifying.md) 文档。历史 Q2/Q3、车队与最快圈可能缺失，保留为空或未知；最快圈使用来源的排名 1，不从冠军或积分推测。
未知开赛时间为 null；UTC 时间带时区；上游故障有缓存时返回 `stale=true`，无缓存时返回 503。

`DATABASE_PATH` 默认 `data/schedules.db`。`CORS_ORIGINS` 默认允许本机端口 3000，用逗号分隔覆盖。
使用 PowerShell `$env:DATABASE_PATH=...` 等设置进程环境变量；`.env.example` 仅是配置清单，不会自动加载。
赛历来源：[Jolpica 文档](https://github.com/jolpica/jolpica-f1/blob/main/docs/README.md)。未来赛历和临时调整取决于上游发布情况。

数据层已按 `DATA_ARCHITECTURE.md` 建立完整的 Temporal + Versioned + Source-Aware 基础结构。当前赛历和成绩链会写入独立的 Season、Circuit、Race、Session、Driver、Team、TeamSeason、Entry、QualifyingResult、StartingGrid、RaceResult、Revision、Provider、ExternalIdentity、RawSource 与 Review 数据；改期和结果变化追加修订，不静默覆盖历史。
Briefing、Evolution、规则、积分、处罚、单圈、轮胎、进站、赛车规格、升级生命周期、采访、来源快照、AI Generation、人工审核和审计表也由同一迁移管理，空缺信息保持 NULL/unknown。现有 API 的 `season-round` 兼容 ID 继续用于路由和提醒，内部 ID 同时出现在 API 读模型中。
数据库启动时执行版本化、事务式迁移；已有 `schedules` 和 `result_cache` 会无损回填，不删除数据库。重要 Provider 响应按内容哈希保留原始记录；缺少外部身份时创建低可信审核项，不根据相似姓名猜测合并。

## 启动 Flutter

本次工作使用仓库忽略的 `.tools/flutter` SDK；也可使用已安装的 Flutter stable。

```powershell
cd mobile
../.tools/flutter/bin/flutter.bat pub get
../.tools/flutter/bin/flutter.bat run -d chrome --web-port=3000
```

默认 `development` 环境使用本地 Backend。Android 模拟器使用
`--dart-define=API_BASE_URL=http://10.0.2.2:8000`；真机测试使用
`--dart-define=API_ENV=test`，连接已配置的 ECS Nginx Backend。真机正式发布
必须使用 HTTPS。iOS 构建需要 macOS/Xcode，Android 构建需要 Android SDK。

本机已安装 Android SDK、Android 35 模拟器镜像及硬件加速驱动，AVD 名为 `F1Reminder_API35`。在仓库根目录运行 `scripts/run-emulator.ps1 -ShowWindow` 可显示模拟器；运行 `scripts/build-android.ps1` 构建连接 ECS 测试 Backend 的调试 APK，或以 `-ApiEnvironment development` 构建本地开发版本。SDK、镜像和构建缓存保留在忽略的 `.tools` 中。
`scripts/reminder-fixture.py` 是独立的模拟赛历服务（端口 8001），配合 `scripts/build-android.ps1 -ApiBaseUrl http://10.0.2.2:8001` 验证连续通知；该数据仅供测试。

## 检查

```powershell
cd backend
.venv/Scripts/python -m unittest discover -s tests -v
cd ../mobile
../.tools/flutter/bin/flutter.bat analyze
../.tools/flutter/bin/flutter.bat test
```

## 结构与约定

- `backend/app/providers`：读取第三方赛历、校验并转换为内部模型。
- `backend/app/data_schema.py`：完整 SQLite Schema、版本迁移、原始来源和 Provider 健康状态。
- `backend/app/repositories`：持久化规范化赛历实体、身份映射和赛程修订，并维护兼容缓存；当季缓存 1 小时、历史赛季 24 小时。
- `mobile/lib/features`：Home、Races 功能；AI/3D 在 App shell 中保留轻量占位。
- `mobile/lib/data`：客户端内部模型及后端访问；不接触上游 schema。
- `mobile/lib/core/theme.dart` 和 `docs/design.md`：信息层级、配色、字体与间距规范。

客户端刷新失败时优先使用 SharedPreferences 中最近一次成功的响应，覆盖 Home、赛季赛历和按需加载的比赛成绩。缓存只作为带 `stale=true` 的离线读路径，不替代后端来源与缓存策略。
开发路线见 `development.md`，先完成 Home + Races MVP，再加入 AI 和 3D。

## 凭据

GitHub token 已由 Git Credential Manager 保存在系统凭据存储，原明文文件已删除。
使用凭据管理器读取凭据，保持 token 不进入代码、日志或提交。
本目录现为独立 Git 仓库，尚未设置 GitHub remote 或推送。
