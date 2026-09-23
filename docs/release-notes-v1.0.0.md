# GrandPrixReminder v1.0.0

Android release APK 已通过最终真机验收。

## 本版内容

GrandPrixReminder 把下一场比赛、赛季赛历、比赛结果、赛后 Briefing 和 Evolution 技术升级串成完整比赛周末流程。Android 客户端提供本地提醒、无剧透、车手/车队关注、简体中文/English 切换，以及可交互的 3D Car Explorer、Upgrade Timeline 与 Ghost Compare。

赛后自动任务使用官方 F1 与车队来源生成结构化内容。Evolution 升级经过原文证据校验和独立模型复核后自动发布，未获支持的候选不会出现在公开 API。原始来源与业务实体保持可追溯；较低置信度的已发布内容带提示。模型复核仍可能误判，用户可以打开来源核对。

## 安装与更新

[GitHub Release](https://github.com/hfdsdfgr/f1-grand-prix-reminder-codex/releases/tag/v1.0.0) 已发布；仓库目前为 private，下载需要仓库权限。发布产物：

- [GrandPrixReminder-v1.0.0.apk](https://github.com/hfdsdfgr/f1-grand-prix-reminder-codex/releases/download/v1.0.0/GrandPrixReminder-v1.0.0.apk)：安装到 Android 手机。
- `GrandPrixReminder-v1.0.0.aab`：留在构建环境供后续应用分发，未上传 GitHub Release。

版本为 `versionName=1.0.0`、`versionCode=1`，使用现有本地 release keystore 签名。将 APK 复制到手机并打开安装。已有相同包名与签名的正式测试版可尝试覆盖更新；Debug 签名与 release 签名不同，Android 不会允许直接覆盖。卸载旧版会删除设备上的本地设置与提醒，请先确认需要保留的数据。

建议安装后检查：启动 → Home 下一场 → Calendar → 一场已结束比赛的 Results / Briefing / Evolution → 3D 部件与来源 → 切换中英文 → 无剧透、关注与提醒 → 后台/恢复 → 断网与重新联网。

## 已知限制

- v1.0 API 当前通过公网 IP `http://8.134.70.237` 提供，HTTP 通信未加密；HTTPS 与域名部署留待 v1.0 之后。
- Evolution 自动复核不能保证技术主张绝对正确；置信度提示与来源链接帮助核查，但不消除误判风险。
- 部分比赛可能没有合格官方技术来源，因此 Evolution 可以为空。现有历史回填覆盖率不保证未来每场比赛都能生成技术内容。

APK 已通过最终真机 smoke test。AAB 保留供后续分发。
