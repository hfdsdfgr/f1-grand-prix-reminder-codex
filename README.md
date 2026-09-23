# GrandPrixReminder

GrandPrixReminder 是一款面向 F1 比赛周末的 Android 赛事助手。它把赛历、成绩、赛后 Briefing 和赛车技术演进放在同一条分站时间线上。当前版本为 **v1.0.0**，Android 真机验收已通过。

## 你可以做什么

- 在 Home 查看下一场比赛、倒计时、周末 Sessions，并设置赛前 24 小时、1 小时、15 分钟或自定义提醒。
- 在 Calendar 和 GP Detail 查看赛季赛程、比赛状态、成绩与赛道轮廓；结果页支持无剧透模式。
- 阅读来自赛后报道的结构化 Briefing，以及车队、部件、生命周期明确的 Evolution 升级历程。
- 在 Evolution 3D Car Explorer 旋转、缩放、切换视角、展开部件，并从部件或时间线打开对应升级及来源；Ghost Compare 可比较两站车辆规格。
- 在设置中切换简体中文 / English，关注车手与车队。语言、关注、无剧透和提醒设置保存在本机。

Flutter 客户端只连接本项目的 FastAPI API。Backend 汇集赛历与结果，并在比赛结束后按既定时序自动发现来源、生成 Briefing 和 Evolution。Evolution 事实先经过证据校验，再由独立模型复核；未获支持的内容不会发布。每条公开升级保留原始来源，低置信度内容在 App 中提示。**模型复核不能保证内容绝对正确。** 找不到合格技术来源时，对应分站可能没有 Evolution 条目。

## 安装 Android v1.0.0

构建产物位于：

- `mobile/build/release-candidate/GrandPrixReminder-v1.0.0.apk`
- `mobile/build/release-candidate/GrandPrixReminder-v1.0.0.aab`（留作后续分发，不直接安装）

将 APK 复制到 Android 手机后打开安装。若手机上已有**同一签名**的正式测试包，Android 可以尝试覆盖更新；若旧包是 Debug 签名，系统会拒绝覆盖。不要为了安装而直接清除应用数据：卸载会移除本机的关注、语言和提醒设置。

## 本地运行与检查（Windows PowerShell）

```powershell
py -3 -m venv backend/.venv
backend/.venv/Scripts/python -m pip install -r backend/requirements.txt
cd backend
.venv/Scripts/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

新终端运行 Flutter；仓库忽略的 `.tools/flutter` 也可替换为已安装的 Flutter SDK：

```powershell
cd mobile
../.tools/flutter/bin/flutter.bat pub get
../.tools/flutter/bin/flutter.bat run
```

`development` 默认连接 `http://127.0.0.1:8000`。Android 模拟器可用 `--dart-define=API_BASE_URL=http://10.0.2.2:8000`；连接现有 ECS 可用 `--dart-define=API_ENV=test`。正式构建必须使用 `API_ENV=production`：

```powershell
./scripts/build-release.ps1
```

该脚本需要本地 `mobile/android/key.properties` 与 `mobile/android/app/grandprix-upload.jks`，并构建已签名 APK/AAB。签名文件和密码均被 Git 忽略。`API_BASE_URL` 可以替换成将来的 HTTPS 域名；当前正式构建仅对 ECS 的 `8.134.70.237` 放行 HTTP 明文连接。

```powershell
cd backend
.venv/Scripts/python -m unittest discover -s tests -q
cd ../mobile
../.tools/flutter/bin/flutter.bat analyze
../.tools/flutter/bin/flutter.bat test
```

## API 与数据

主要只读接口：`/api/v1/next-race`、`/api/v1/races?season=2026`、`/api/v1/races/{season}-{round}/results`、`/api/v1/races/{season}-{round}/briefing`、`/api/v1/evolution/{season}-{round}`。Briefing 与 Evolution 支持 `?lang=en` / `?lang=zh-CN`；缺少译文时回退英文，来源和业务实体 ID 不随语言变化。`GET /health` 可用于服务健康检查。

当前服务路径是 Internet → ECS Nginx (`:80`) → 本机 FastAPI (`127.0.0.1:8000`)。DeepSeek API Key 仅在服务器 systemd EnvironmentFile 中提供，客户端、Git 和 APK 不包含该密钥。数据设计见 [DATA_ARCHITECTURE.md](DATA_ARCHITECTURE.md)，客户端说明见 [mobile/README.md](mobile/README.md)。

## 已知限制

- v1.0 Backend 使用公网 IP + HTTP，通信未加密；HTTPS 与域名尚未部署。
- Evolution 的自动模型复核仍有误判风险；低置信度提示不能替代对原始来源的核对。
- 部分比赛缺少合格官方技术来源，历史回填覆盖率不代表未来每场比赛都有数据。

详见 [v1.0.0 Release Notes](docs/release-notes-v1.0.0.md) 与 [CHANGELOG.md](CHANGELOG.md)。
