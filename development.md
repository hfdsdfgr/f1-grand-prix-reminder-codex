GrandPrixReminder Development Guide

1. 项目概述

项目名称： GrandPrixReminder

产品定位：

GrandPrixReminder 是一款轻量级 Formula 1 赛事助手，核心围绕四个能力展开：

下一场大奖赛时间查询与系统提醒

F1 历史大奖赛数据查询

基于 AI 的赛后车手采访信息提炼

各车队赛车升级历史与交互式 3D 技术可视化

产品不定位为传统 F1 新闻客户端，也不追求覆盖所有 F1 内容。

核心目标是：

Race. Debrief. Evolution.

即让用户快速知道：

下一场比赛什么时候开始

过去的比赛发生了什么

车手赛后真正透露了什么有效信息

各车队在不同阶段对赛车进行了什么升级

整个产品应保持轻量、快速、简洁、低学习成本。

2. 核心开发原则

2.1 Lightweight First

GrandPrixReminder 首先是一款轻量级工具，而不是大型 F1 综合平台。

任何新增功能在开发前必须判断：

是否属于核心使用场景

是否明显提高用户体验

是否造成不必要的复杂度

是否与现有功能重复

是否会让产品逐渐变成普通 F1 新闻 App

如果功能不能明显提升核心体验，应优先不开发。

2.2 Data First, AI Second

能够通过结构化数据、确定性算法或数据库完成的功能，不得默认使用大语言模型。

例如：

比赛时间

倒计时

比赛结果

发车顺位

最快圈

单圈数据

车手信息

车队信息

Pit Stop

轮胎 Stint

排位结果

历史数据

全部由 API、数据库和程序逻辑处理。

AI 仅用于传统程序难以直接完成的非结构化信息处理，例如：

采访内容理解

去除客套话

技术信息提取

多车手观点整合

赛车升级相关表述提取

Race Brief 生成

禁止为了体现“AI”而强行将普通数据功能接入 LLM。

2.3 Source First

所有赛事数据、采访信息和赛车升级信息必须尽可能保留数据来源。

不得让 AI 自行生成：

赛车升级

技术参数

采访内容

比赛数据

车手观点

AI 只能对已有可信来源进行提取、分类、压缩和总结。

无法确认的信息应标记为：

Unverified

而不是自动补全。

2.4 User Experience First

用户打开 App 后，应在最短时间内完成主要操作。

原则：

首页不堆叠信息

避免复杂导航

避免大量弹窗

避免不必要的设置

避免强制登录

避免多级菜单

避免大量卡片嵌套

避免为了视觉效果牺牲操作效率

3. 产品信息架构

App 底部导航固定为四个主要页面：

Home
Races
Briefing
Evolution

除 Settings 等必要辅助页面外，不轻易增加一级导航。

4. Home — 下一站大奖赛

Home 是整个 App 使用频率最高的页面。

核心任务只有一个：

告诉用户下一场 F1 比赛是什么，以及什么时候开始。

首页主要显示：

Singapore Grand Prix

Marina Bay Street Circuit

21 Sep · 20:00

Race starts in

07D 03H 42M

同时显示完整 Race Weekend：

FP1
FP2
FP3
Sprint
Sprint Qualifying
Qualifying
Race

根据不同大奖赛实际 Session 自动显示，不存在的 Session 不显示。

4.1 自动时区转换

API 获取的赛事时间必须转换为用户设备本地时区。

用户原则上不需要手动计算比赛所在地与所在地之间的时差。

4.2 通知

支持：

Race Reminder

Qualifying Reminder

Sprint Reminder

自定义提前时间

推荐默认选项：

24 Hours Before
1 Hour Before
15 Minutes Before
Custom

系统通知必须使用设备本地通知能力。

第一阶段不依赖服务器 Push Notification。

4.3 首页限制

首页第一版本不加入：

新闻 Feed

积分榜

商城

社区

视频推荐

大量车手数据

广告式 Banner

首页必须保持极简。

5. Races — 历史赛事数据库

Races 页面负责查询历届大奖赛。

5.1 年份选择

用户可以选择：

2026
2025
2024
...

显示对应赛季大奖赛。

5.2 大奖赛列表

每场比赛至少显示：

Grand Prix
Date
Circuit
Winner
Fastest Lap

例如：

Japanese Grand Prix

Suzuka Circuit
12 Apr

Winner
Lando Norris

Fastest Lap
1:31.xxx

5.3 Race Detail

进入比赛后显示：

Race Result

Position
Driver
Team
Grid
Time / Gap
Status
Points

Fastest Lap

Driver
Lap
Lap Time

Qualifying

Position
Driver
Q1
Q2
Q3

后续版本可加入：

Lap Time

Sector Time

Tyre Stint

Pit Stop

Weather

Safety Car

Position Change

DNF

5.4 数据来源

优先考虑：

OpenF1

Jolpica F1 API

其他可靠公开 F1 数据源

API 层必须抽象。

禁止 UI 直接依赖某一个第三方 API 的原始 JSON Schema。

统一转换为内部数据模型：

External API
      ↓
Data Provider
      ↓
Normalizer
      ↓
Internal Model
      ↓
Repository
      ↓
UI

这样未来更换数据源时无需重写 UI。

6. Briefing — AI Race Debrief

Briefing 是 GrandPrixReminder 的核心 AI 功能。

目标不是生成普通比赛新闻，而是：

从大量车手赛后采访中提取真正具有信息价值的内容。

6.1 输入内容

可能包括：

Post-Race Interview

Driver Interview

Team Interview

Press Conference

官方新闻发布

Team Statement

所有输入必须保存：

Source
URL
Published Time
Driver
Team
Grand Prix
Original Text

以便追踪来源。

6.2 AI Pipeline

标准处理流程：

Raw Interview
      ↓
Text Cleaning
      ↓
PR / Courtesy Filtering
      ↓
Information Extraction
      ↓
Fact Classification
      ↓
Structured JSON
      ↓
Driver Brief
      ↓
Race Brief

6.3 去除低价值内容

优先剔除：

感谢车队

感谢车迷

常规祝贺

“We'll keep pushing”

“It was a difficult race”

没有具体信息的情绪表达

重复信息

公关式套话

但如果类似表述包含真实信息，则必须保留。

例如：

"It was difficult because we suffered front tyre overheating after lap 15."

虽然包含 “difficult”，但后半句包含明确技术信息，因此不得删除。

6.4 Driver Brief 数据结构

建议统一输出：

{
  "driver": "",
  "team": "",
  "grand_prix": "",
  "race_assessment": [],
  "car_strengths": [],
  "car_weaknesses": [],
  "strategy": [],
  "tyres": [],
  "upgrades": [],
  "incidents": [],
  "future_expectations": [],
  "key_quotes": [],
  "sources": []
}

6.5 Race Brief

在 Driver Brief 基础上进一步生成 Race Brief。

主要提取：

Major Technical Theme

Team Performance

Tyre Issues

Strategy Issues

Upgrade Feedback

Driver Concerns

Next-Race Expectations

Race Brief 必须尽可能避免重复比赛结果。

例如：

错误：

Norris won the race ahead of Verstappen.

如果该信息已经在 Races 页面显示，就没有必要在 AI Brief 中重复。

更有价值的是：

McLaren drivers consistently reported improved high-speed stability,
while low-speed mechanical grip remained a weakness.

7. Evolution — 赛车升级档案

Evolution 是 GrandPrixReminder 最重要的差异化功能。

目标：

建立可交互的 F1 赛车技术升级历史数据库。

7.1 页面结构

用户首先选择：

Season
      ↓
Team
      ↓
Grand Prix

例如：

2026

McLaren

Japanese Grand Prix

7.2 Upgrade Timeline

显示车队整个赛季的主要升级：

Australia
│
├── Front Wing
│
Japan
│
├── Floor
│
Imola
│
├── Rear Wing
│
Spain
│
└── Sidepod

7.3 Upgrade 数据结构

每次升级至少保存：

{
  "season": 2026,
  "team": "",
  "grand_prix": "",
  "component": "",
  "change": "",
  "goal": "",
  "expected_effect": "",
  "driver_feedback": [],
  "status": "",
  "sources": []
}

status 可以包括：

Introduced
Tested
Retained
Modified
Removed
Unknown

8. Interactive Car Model

Evolution 页面中央使用简化 F1 赛车 3D 模型。

目标不是工程级 CFD/CAD 模型。

目标是：

用简单直观的方式告诉普通用户赛车哪个位置发生了变化。

8.1 模型原则

第一版本只建立一套 Generic Formula Car。

不得为每支车队重新制作高精度赛车。

模型主要分为：

Car
├── Front Wing
├── Nose
├── Front Suspension
├── Front Tyres
├── Sidepods
├── Floor
├── Engine Cover
├── Power Unit
├── Rear Suspension
├── Rear Tyres
├── Beam Wing
└── Rear Wing

每个部件必须可以独立：

Highlight

Select

Focus

Attach Annotation

8.2 模型格式

推荐：

Blender
   ↓
GLB / glTF
   ↓
App

尽量降低 Polygon 数量。

移动端必须优先保证：

加载速度

帧率

内存占用

而不是模型精度。

8.3 Annotation

模型周围显示技术信息框：

              Rear Wing
                  │
                  ↓

Front Wing → [ CAR ] ← Floor
                  ↑
                  │
               Sidepod

信息框应通过连线指向对应赛车区域。

点击部件后显示：

FLOOR

Introduced
Japanese GP

Change
Revised floor-edge geometry

Goal
Improve airflow stability

Driver Feedback
Improved rear stability

8.4 Upgrade Highlight

如果当前大奖赛存在：

component = floor

则：

floor → Highlight

其他部件降低视觉强调。

不得同时让大量部件高亮造成视觉混乱。

9. 技术架构

推荐技术栈：

Mobile

Flutter
Dart

负责：

UI

Navigation

Local Storage

Notification

API Communication

3D Viewer

Backend

Python
FastAPI

负责：

F1 API 聚合

数据标准化

Interview Pipeline

LLM 调用

Upgrade 数据管理

Cache

Database

MVP：

SQLite

未来：

PostgreSQL

3D

Blender
GLB / glTF

10. Backend Architecture

推荐结构：

backend/

app/
├── api/
├── models/
├── schemas/
├── services/
├── repositories/
├── providers/
├── ai/
├── database/
├── core/
└── tests/

providers

负责第三方数据：

providers/
├── openf1.py
├── jolpica.py
└── interview_sources.py

services

负责业务逻辑：

services/
├── race_service.py
├── schedule_service.py
├── driver_service.py
├── briefing_service.py
└── evolution_service.py

ai

所有 LLM 逻辑集中：

ai/
├── client.py
├── prompts/
├── extractors/
├── filters/
└── validators/

禁止将 Prompt 散落在 API Route 或 UI 中。

11. Flutter Architecture

推荐：

lib/

├── core/
├── data/
├── domain/
├── features/
└── shared/

Feature：

features/

├── home/
├── races/
├── briefing/
├── evolution/
└── settings/

每个 Feature 独立维护自己的：

data
domain
presentation
widgets

避免所有代码集中在：

screens/
widgets/
utils/

形成不可维护结构。

12. API 设计

GrandPrixReminder App 只访问自己的 Backend。

推荐：

GET /api/v1/next-race

GET /api/v1/seasons

GET /api/v1/races

GET /api/v1/races/{race_id}

GET /api/v1/races/{race_id}/results

GET /api/v1/races/{race_id}/laps

GET /api/v1/briefings/{race_id}

GET /api/v1/briefings/{race_id}/drivers

GET /api/v1/evolution/{season}/{team}

GET /api/v1/evolution/{season}/{team}/{race_id}

不要让 Flutter App 同时直接调用多个第三方 API。

13. Cache

F1 历史数据不会频繁改变。

因此必须合理缓存。

例如：

Historical Race Results
→ Long-term Cache

Past Qualifying
→ Long-term Cache

Next Race
→ Short Cache

Current Weekend
→ Short Cache

AI Brief
→ Generate Once + Store

尤其 AI Brief：

不得每次用户打开页面重新调用 LLM。

正确方式：

Interview
     ↓
Generate
     ↓
Validate
     ↓
Database
     ↓
App

这可以显著降低 API 成本。

14. AI Provider Abstraction

不得把项目绑定到单一 AI Provider。

建立统一接口：

LLMProvider

generate()
extract()
summarize()

未来可以支持：

OpenAI
DeepSeek
Gemini
Claude
Other OpenAI-Compatible API

业务逻辑不得直接依赖具体 SDK。

15. UI / UX Design Language

GrandPrixReminder 整体设计方向：

Minimal / Motorsport / Technical / Premium

但不得做成传统赛车游戏 UI。

15.1 基础原则

避免：

大面积渐变

AI 风格紫蓝色

过多发光效果

大量圆角卡片

每个区域都加边框

复杂 Dashboard

信息密度过高

优先：

大面积留白

强 Typography

清晰层级

少量强调色

极简图标

细分割线

数据驱动布局

15.2 圆角

只在真正需要表达独立交互区域时使用圆角组件。

禁止：

Card inside Card inside Card

15.3 Team Color

车队颜色可以作为局部强调色。

例如 Evolution：

McLaren → Papaya Accent
Ferrari → Red Accent
Mercedes → Teal Accent

但不得让整个页面背景随车队变色。

16. Performance

GrandPrixReminder 是轻量级 App。

因此：

App Startup

尽可能减少启动阶段网络请求。

3D

模型按需加载。

用户未进入 Evolution 时不得加载赛车模型。

Images

使用：

WebP / AVIF

并合理缓存。

API

优先：

Cache
→ Database
→ External API

而不是每次直接请求第三方服务。

17. Error Handling

所有网络功能必须存在：

Loading
Success
Empty
Error
Offline

五种基本状态。

禁止：

API Error
→ Blank Screen

历史赛事数据应尽可能支持离线缓存。

18. Security

所有 API Key 必须保存在 Backend。

Flutter 中禁止包含：

LLM API Key
Private API Key
Database Credentials

客户端只访问 GrandPrixReminder Backend。

19. Development Roadmap

Phase 1 — Core Reminder

完成：

Flutter 基础项目

FastAPI Backend

F1 API Provider

Next Race

Race Weekend Sessions

Local Time Conversion

Countdown

Local Notification

基础 UI

目标：

GrandPrixReminder 已经可以作为真正的赛事提醒 App 使用。

Phase 2 — Race Database

完成：

Seasons

Race List

Race Result

Qualifying

Fastest Lap

Driver

Team

Local Cache

目标：

用户可以查询历史大奖赛。

Phase 3 — AI Briefing

完成：

Interview Source

Text Cleaning

LLM Provider

Information Extraction

Driver Brief

Race Brief

Source Tracking

AI Cache

目标：

用户能够快速获取赛后采访中的有效信息。

Phase 4 — Evolution Database

完成：

Team

Season

Grand Prix

Component

Upgrade

Upgrade Timeline

Source Tracking

暂时不开发 3D。

目标：

先确保升级数据库本身正确可靠。

Phase 5 — Interactive Car

完成：

Generic Formula Car

GLB/glTF

3D Viewer

Rotation

Zoom

Component Selection

Highlight

Annotation

目标：

将 Evolution 数据与赛车模型关联。

Phase 6 — Evolution Experience

完成：

Season
→ Team
→ Grand Prix
→ Upgrade
→ Component Highlight

加入：

Timeline

Before / After

Upgrade Comparison

Driver Feedback

形成完整 Evolution Experience。

Phase 7 — Optimization

完成：

Performance

Cache

Offline

Animation

UI consistency

Error handling

Accessibility

Testing

README

Demo GIF / Video

20. MVP Definition

真正的 MVP 只包含：

Home
+
Races

即：

Next Race
Race Weekend
Countdown
Notification
Historical Races
Race Results
Fastest Lap

Briefing 和 Evolution 属于产品差异化功能，但不是 MVP 的必要条件。

必须先完成稳定 MVP，再进入 AI 与 3D。

21. Feature Review Rule

当提出任何新功能时，在直接实现之前必须进行一次 Feature Review。

至少判断：

1. 是否符合 GrandPrixReminder 产品定位？
2. 是否真正解决用户问题？
3. 是否已经存在类似功能？
4. 是否可以通过更简单的方法实现？
5. 是否增加明显维护成本？
6. 是否增加不必要的 AI 依赖？
7. 是否影响 App 的轻量化？
8. 是否影响现有架构？

如果新需求存在明显问题，不应机械执行。

应说明问题，并提出更合理的替代方案。

22. Reference Existing Projects

开发新模块之前，应主动研究：

GitHub 开源项目

F1 数据工具

Motorsport Apps

Sports Reminder Apps

3D Product Viewer

Data Visualization Projects

AI News / Interview Summarization Projects

研究重点：

Architecture
UX
Data Model
API Design
Performance
Interaction
Error Handling

不得直接复制代码或 UI。

目标是：

Research
   ↓
Understand
   ↓
Compare
   ↓
Improve
   ↓
Implement

23. Code Quality

代码必须：

模块化

易读

可测试

可维护

避免重复

避免超大型文件

避免无意义抽象

避免过度工程化

任何单个模块开始明显承担多个职责时，应考虑拆分。

24. Documentation

重要模块必须说明：

Purpose
Input
Output
Dependencies
Failure Cases

尤其：

Data Provider

AI Pipeline

Notification

Cache

Evolution

3D Component Mapping

必须保持文档与代码同步。

25. Testing

至少覆盖：

Backend

API Normalization
Race Data
Time Conversion
AI JSON Validation
Cache
Evolution Mapping

App

Navigation
Countdown
Notification
Race Loading
Offline State
Error State

Evolution

重点测试：

Upgrade
      ↓
Component ID
      ↓
3D Mesh

映射是否正确。

26. Git Strategy

推荐：

main
develop
feature/*
fix/*

Commit 应描述实际修改：

feat: add next race countdown

feat: add race result repository

feat: add driver briefing extraction

feat: add evolution component mapping

fix: handle missing qualifying session

避免：

update

fix

changes

test123

27. Definition of Done

功能只有满足以下条件才算完成：

✓ Feature works
✓ Error state handled
✓ Loading state handled
✓ Data validated
✓ UI consistent
✓ No exposed secrets
✓ Tests passed
✓ Documentation updated
✓ No obvious performance regression

28. Non-Goals

GrandPrixReminder 当前不计划成为：

F1 社交平台

赛车直播平台

视频平台

博彩平台

Fantasy F1 平台

F1 商城

通用体育 App

综合赛车新闻客户端

这些功能不得因为“其他 F1 App 有”而自动加入。

29. Long-Term Product Identity

GrandPrixReminder 的核心产品结构始终保持：

            GrandPrixReminder

                   │
     ┌─────────────┼─────────────┐
     │             │             │
    RACE        DEBRIEF       EVOLUTION
     │             │             │
When?          Why?          What changed?

Home 回答：

When is the next race?

Races 回答：

What happened?

Briefing 回答：

What did the drivers actually reveal?

Evolution 回答：

What changed on the cars?

所有未来功能都应围绕这四个问题扩展。

如果某项功能无法明显服务其中至少一个问题，应谨慎加入。

30. Final Development Principle

GrandPrixReminder 的竞争力不来自功能数量，而来自：

Fast
Simple
Reliable
Technical
Useful

开发过程中始终优先：

正确的数据
>
清晰的信息
>
简单的交互
>
稳定的性能
>
视觉效果
>
功能数量

尤其不要为了 AI 或 3D 而牺牲整个 App 的轻量化。

GrandPrixReminder 最终应该是一款：

打开 3 秒就能知道下一场比赛什么时候开始，需要深入了解时又能够查看比赛数据、AI 赛后情报以及赛车技术升级历史的轻量级 F1 工具。

GrandPrixReminder Development Guide — Additional Product Requirements

31. Product Audience

GrandPrixReminder 的核心用户为：

Formula 1 Fans

产品不是专业车队工程工具，也不是单纯的数据分析平台。

核心目标是帮助普通及进阶 F1 车迷更方便地完成：

比赛前 → 什么时候比赛？ 比赛周末 → 现在进行到哪里？ → 这个周末发生了什么？ 比赛后 → 这场比赛是怎么发展的？ → 为什么有人赢 / 输？ 深入了解 → 车手真正说了什么？ → 赛车发生了什么技术变化？

所有新功能都应优先判断：

Does this help an F1 fan understand or follow a race weekend better?

如果不能，则不应因为"技术上可以实现"而加入。

32. Product Usage Lifecycle

GrandPrixReminder 应围绕完整 F1 Weekend 生命周期设计：

PRE-RACE │ ├── Calendar ├── Next Race └── Reminder RACE WEEKEND │ ├── Weekend Hub ├── Session Status └── Weekend Highlights POST-RACE │ ├── Race Story ├── Strategy View └── Championship Impact DEEP DIVE │ ├── Briefing └── Evolution

不同功能承担不同职责：

Reminder → Bring user back Weekend Hub → Keep user informed Race Story → Explain what happened Strategy → Explain why it happened Briefing → Explain what drivers revealed Evolution → Explain what changed on the cars

33. Weekend Hub

新增：

Weekend Hub

Weekend Hub 是比赛周末期间 GrandPrixReminder 的核心入口。

当进入当前 Grand Prix Weekend 时，应突出展示该站最新状态。

33.1 Weekend Sessions

展示当前周末全部 Session：

FP1 FP2 FP3 Sprint Qualifying Sprint Qualifying Race

实际 Session 必须来自 Backend，不允许前端硬编码固定周末结构。

示例：

Japanese Grand Prix FP1 Completed FP2 Completed FP3 15:00 Qualifying 18:00 Race Tomorrow · 17:00

需要明确区分：

Upcoming Live Completed Delayed Cancelled

具体状态数据规则遵循 DATA_ARCHITECTURE.md。

33.2 Weekend Story

Weekend Hub 可以提供一个轻量：

Weekend Story

用于告诉用户：

What matters this weekend?

示例：

Weekend Story • McLaren showed strong long-run pace in FP2 • Ferrari struggled in low-speed corners • Red Bull tested a revised floor • Rain could affect qualifying

Weekend Story 不应该变成新闻 Feed。

目标不是展示：

20 Articles

而是：

Many Sources ↓ Few Important Things

33.3 Weekend Story Scope

Weekend Story 最多突出少量真正重要的信息。

优先：

Performance Technical Changes Weather Impact Penalties Incidents Strategy Context Important Driver Comments

不要加入：

Celebrity News Paddock Gossip Merchandise Generic Social Media Content

34. Spoiler-Free Mode

新增：

Spoiler-Free Mode

用于尚未观看比赛或排位赛的用户。

34.1 Behaviour

开启后，对于已经结束但用户可能尚未观看的 Session：

不得直接显示：

Winner Podium Final Classification Fastest Lap Championship Changes Race Story Briefing Conclusions

改为：

Race Completed Results Hidden [ Reveal Results ]

34.2 Spoiler Scope

Spoiler-Free Mode 应同时作用于：

Home Races Weekend Hub Notifications Race Story Briefing Championship Impact

避免 Home 隐藏结果，但 Notification 又直接显示：

Norris wins Japanese GP

34.3 Reveal

用户必须可以主动：

Reveal This Session

或者：

Disable Spoiler-Free Mode

不需要复杂权限系统。

35. Driver and Team Follow

支持用户关注：

Drivers Teams

例如：

Following Lando Norris Oscar Piastri McLaren

MVP 阶段优先使用本地存储。

除非后续需要：

Multi-device Sync Cloud Preferences Account System

否则不要为了 Follow 功能强制引入登录。

35.1 Follow Usage

Follow 不应只是收藏列表。

它应该影响：

Home Priority Weekend Hub Briefing Ordering Evolution Ordering Notifications

例如：

Your Drivers Lando Norris P2 · Starts P4

或：

McLaren New floor update available

35.2 Follow Notifications

未来可以支持：

Driver Brief Available Team Upgrade Available Important Penalty Race Reminder

但不要做：

Every News Article Notification

避免通知骚扰。

36. Race Story

Race Detail 页面增加：

Race Story

目的不是重复最终结果，而是解释：

How did the race unfold?

36.1 Timeline

Race Story 使用关键事件时间线。

例如：

Lap 1 Verstappen keeps the lead Lap 18 McLaren extends the first stint Lap 24 Safety Car changes the pit window Lap 31 Norris takes the effective lead Lap 46 Ferrari switches Leclerc to Soft Lap 53 Norris wins

36.2 Event Priority

Race Story 只保留真正影响比赛发展的事件：

Lead Changes Important Overtakes Pit Stops Safety Car VSC Red Flag Major Incidents Penalties Strategy Changes Mechanical Problems Weather Changes

36.3 Data First, AI Second

Race Story 应遵循：

Structured Race Data ↓ Event Detection ↓ Important Event Selection ↓ AI Narrative

不要：

LLM ↓ Guess what happened

结构化比赛数据负责事实。

AI 只负责：

Summarize Connect Explain

36.4 Key Insights

Race Story 可以额外生成少量：

Key Turning Point Strategy Winner Biggest Gain Biggest Loss

必须能够由比赛数据或可靠来源支撑。

37. Strategy View

Race Detail 页面增加轻量：

Strategy View

目标是让普通车迷快速理解：

Who used which tyres and when?

37.1 Primary Visualization

核心展示：

NOR Medium ───────── Hard ───────────── VER Soft ─────── Hard ───────────────── LEC Medium ───────────── Soft ─────────

主要展示：

Tyre Compound Stint Length Pit Lap Number of Stops

37.2 Driver Detail

点击车手后可以展示：

Stops Pit Laps Stint Length Tyre Compound Tyre Age

如果数据可靠，也可以展示：

Undercut Overcut Tyre Offset

但必须基于实际数据推导。

37.3 Scope

Strategy View 当前不做：

Live Telemetry Throttle Trace Brake Trace Gear Trace Full Race Engineer Simulation Complex Predictive Strategy Model

定位是：

Fan-friendly post-race strategy explanation.

38. Championship Impact

赛后页面可以增加：

Championship Impact

目的不是简单复制积分榜，而是说明：

What did this race change?

38.1 Driver Championship

例如：

Drivers' Championship 1 Norris 248 2 Verstappen 231 -17 3 Leclerc 205 -43

38.2 Race Impact

增加：

Championship Impact Norris Championship lead +7 Verstappen Lost 8 points relative to Norris McLaren Constructors lead extends to 52 points

38.3 Title Scenarios

仅在数学上有意义的赛季阶段考虑：

Title Scenarios

例如：

Norris can clinch the championship if...

该功能必须由数学计算产生。

禁止让 LLM 自行计算夺冠条件。

AI 可以解释结果，但不得负责核心积分数学。

39. Circuit Layout

每个 Grand Prix Detail 页面显示该站：

Circuit Layout

本功能定位：

Lightweight Circuit Visualization

目的只是帮助车迷快速识别赛道。

39.1 Visual Scope

主要展示：

Circuit Shape Turn Numbers Selected Famous Corner Names

例如：

T1 T3 T8 T14 Eau Rouge 130R Spoon Curve Casino Square Wall of Champions

不做复杂赛道地图。

39.2 Asset Format

赛道轮廓优先使用：

SVG

而不是：

AI Generated PNG

原因：

Scalable Small File Size Transparent Theme Friendly Easy Label Overlay

赛道属于事实性几何数据。

禁止使用生成式 AI 自行绘制赛道轮廓。

39.3 SVG Standard

所有 Circuit SVG 应统一：

viewBox padding stroke width line style transparent background

并适配：

Light Theme Dark Theme

不要在 SVG 中写死无法覆盖的主题颜色。

40. Turn Numbers

Circuit Layout 可以显示：

T1 T2 T3 ...

但视觉优先级低于赛道轮廓。

如果全部 Turn number 导致画面拥挤：

优先显示：

Important Turns Famous Corners

不要为了完整编号破坏页面简洁度。

41. Famous Corner Labels

允许为少量著名弯角增加名称。

原则：

Famous corners should be annotations, not the main content.

名称必须来自可靠数据。

不得由 AI 根据赛道位置自行创造昵称。

41.1 Label Data

Label 至少需要：

turn_number display_name label_position is_notable

仅：

is_notable = true

的弯角默认显示名称。

42. Circuit Visualization Scope Rule

当前 Circuit 功能明确不开发：

Interactive Track Map Live Driver Tracking Sector Visualization DRS Visualization Telemetry Weather Map Race Replay Satellite Map Map SDK

除非未来明确提出需求。

禁止为了显示一个赛道轮廓引入：

Google Maps SDK Mapbox WebView Large Mapping Dependencies

当前实现应保持：

SVG + Small Label Overlay

43. Grand Prix Detail

结合现有功能，Grand Prix Detail 页面建议形成统一信息层级：

Grand Prix Circuit Layout Circuit Name Date / Local Time Weekend Sessions Race Result Race Story Strategy Briefing Technical Evolution

不要一次性将所有内容全部展开。

使用清晰的信息层级或 Section 组织。

44. Pre-Race Grand Prix Detail

比赛尚未开始：

重点：

Circuit Weekend Schedule Countdown Reminder

不显示无意义的空：

Race Story Strategy Result

45. Live Weekend Grand Prix Detail

比赛周末期间：

重点：

Current Session Next Session Weekend Status Circuit Weekend Story

46. Post-Race Grand Prix Detail

比赛结束后：

重点转为：

Result Race Story Strategy Championship Impact Briefing Evolution

Grand Prix Detail 应根据比赛生命周期调整内容优先级，而不是永远显示完全相同的静态页面。

47. Information Density Rule

GrandPrixReminder 面向车迷，但不应该变成：

F1 Data Dashboard.

UI 必须保持：

Readable Lightweight Focused Progressive

复杂数据采用：

Overview ↓ Tap ↓ Details

而不是首页一次显示全部。

48. AI Usage Rule

新增功能继续遵守：

Data First, AI Second.

以下功能主要依赖结构化数据：

Schedule Results Strategy Championship Circuit Turn Numbers Standings

以下功能可以使用 AI：

Weekend Story Race Story Narrative Briefing Upgrade Explanation

即使使用 AI，也必须：

Structured Data / Source ↓ AI ↓ Human-readable Explanation

禁止：

AI ↓ Invent F1 Facts

49. Feature Priority

基于当前项目状态，新增功能建议优先级：

P0 Existing Home Completion Existing Calendar Completion Grand Prix Detail Circuit Layout Weekend Hub Spoiler-Free Mode

然后：

P1 Driver / Team Follow Race Story

然后：

P2 Strategy View Championship Impact

差异化模块：

P3 Briefing Evolution Interactive 3D Car

50. Existing Work Protection Rule

当前：

Frontend Framework + Home Backend + Calendar Backend

已经完成基础连接。

新增功能不得无必要重构这些已经正常工作的模块。

Codex 在实施新需求前必须判断：

Can existing architecture support it? Can it be added incrementally? Does it require migration? Will it break current API contracts?

优先：

Incremental Development

而不是：

Rewrite Everything

51. Product Scope Protection

GrandPrixReminder 当前不计划开发：

Social Network Public Comment System Live Video Race Streaming Full Live Telemetry Betting Fantasy F1 Merchandise Generic F1 News Feed Complex Community Features

如果未来提出类似功能，必须先执行 Feature Review Rule。

52. Updated Product Identity

GrandPrixReminder 不再仅定义为：

F1 Race Reminder.

长期产品定位：

A lightweight F1 race weekend companion for fans.

核心能力：

REMIND When is the race? FOLLOW What is happening this weekend? UNDERSTAND How did the race unfold? ANALYZE Why did it happen? DEBRIEF What did the drivers actually reveal? EVOLVE What changed on the cars?

53. Final Product Rule

GrandPrixReminder 不追求：

More F1 content.

而追求：

Less searching, better understanding.

每个新增功能必须至少解决以下问题之一：

When is it? What happened? Why did it happen? What matters? What did the driver reveal? What changed on the car?

如果某功能不能明显改善其中任何一个问题，则默认不加入当前产品范围。