# GrandPrixReminder Data Architecture

## 1. Document Purpose

本文件定义 GrandPrixReminder 的核心数据架构、实体关系、时间模型、版本模型、数据来源管理和历史数据完整性规则。

本文件是以下模块进行数据设计时的主要约束：

```text
Home
Races
Briefing
Evolution
Notification
AI Pipeline
Data Sync
External Providers
```

`development.md` 负责定义：

> 项目应该如何开发。

`DATA_ARCHITECTURE.md` 负责定义：

> GrandPrixReminder 的数据应该如何存在、关联、变化和被追踪。

# 2. Core Architecture Principle

GrandPrixReminder 不应被设计成静态 F1 数据库。

F1 数据具有明显的：

```text
Temporal
Versioned
Source-dependent
Event-driven
Historical
```

特征。

因此核心原则为：

> Temporal + Versioned + Source-Aware Data Model

## 2.1 禁止 Current State 覆盖 Historical State

错误：

```text
Driver
└── current_team
```

然后所有历史页面通过 `current_team` 查询车队。

正确：

```text
Driver
│
└── DriverTeamAssignment
     ├── team
     ├── season
     ├── valid_from
     └── valid_to
```

历史数据必须回答：

```text
What was true at that time?
```

而不仅仅是：

```text
What is true now?
```

# 3. Universal Data Rules

所有重要实体根据需要支持：

```text
internal_id

created_at
updated_at

valid_from
valid_to

source
source_id

status
version
```

并非所有表必须机械包含全部字段，但涉及历史变化的数据必须考虑：

```text
Time
Version
Source
Status
```

# 4. Internal Identity

GrandPrixReminder 必须拥有自己的内部 ID。

禁止：

```text
OpenF1 driver ID
=
GrandPrixReminder driver ID
```

禁止：

```text
FIA team name
=
Database primary key
```

统一使用：

```text
driver_id
team_id
race_id
session_id
car_model_id
upgrade_id
interview_id
```

这些 ID 属于 GrandPrixReminder。

# 5. External Identity Mapping

第三方数据通过 Mapping 层关联内部实体。

例如：

```text
Driver

drv_001
│
├── OpenF1 → external_xxx
├── Jolpica → external_xxx
├── FIA → external_xxx
└── Formula1.com → external_xxx
```

建立：

```text
DriverExternalIdentity
TeamExternalIdentity
RaceExternalIdentity
CircuitExternalIdentity
```

## 5.1 External Identity Schema

建议：

```text
external_identity_id
internal_entity_id

provider
external_id
external_name

first_seen_at
last_seen_at
last_verified_at

confidence
status
```

# 6. Identity Resolution

不同 Provider 的实体需要经过：

```text
External Data
↓
Identity Resolver
↓
Internal Entity
```

Driver 可以使用：

```text
Full Name
Driver Code
Date of Birth
Nationality
Car Number
Season
Team
```

辅助匹配。

不得仅根据姓名相似度自动合并。

## 6.1 Confidence Policy

```text
High Confidence
→ Automatic

Medium Confidence
→ Automatic + Flag

Low Confidence
→ Manual Review
```

无法可靠判断：

```text
DO NOT GUESS
```

# 7. Season

`Season` 是 GrandPrixReminder 的核心一级实体。

建议：

```text
Season

season_id
year

start_date
end_date

status
regulation_set_id
```

状态：

```text
upcoming
active
completed
```

# 8. Driver

Driver 表示车手长期个人身份。

```text
Driver

driver_id

full_name
given_name
family_name

nationality
date_of_birth

permanent_number

created_at
updated_at
```

Driver 不保存永久的：

```text
team_id
```

作为历史车队关系。

# 9. Driver Team Assignment

车手和车队通过：

```text
DriverTeamAssignment
```

建立时间关系。

建议：

```text
assignment_id

driver_id
team_id
season_id

car_number

role

valid_from
valid_to

race_from
race_to

status
```

## 9.1 Role

支持：

```text
full_time
reserve
replacement
rookie
guest
test
```

## 9.2 Mid-Season Driver Change

必须支持：

```text
Driver A

Round 1–8
Team X

Round 9–24
Team Y
```

以及：

```text
Driver B

Round 1–12
Full Time

Round 13
Replaced

Round 14+
Returned
```

# 10. Team

Team 表示长期车队实体。

```text
Team

team_id

canonical_name
country

created_at
updated_at
```

Team 不应直接承担所有赛季属性。

# 11. TeamSeason

建立：

```text
TeamSeason
```

描述某车队在具体赛季的参赛状态。

```text
team_season_id

team_id
season_id

display_name
constructor_name

car_name

engine_supplier

team_color

valid_from
valid_to
```

## 11.1 TeamSeason 解决的问题

支持：

```text
Team Rename
Constructor Rename
Ownership Change
Engine Supplier Change
Car Name Change
Brand Change
```

# 12. Power Unit Manufacturer

动力单元供应商建议独立建模：

```text
PowerUnitManufacturer

pu_manufacturer_id
name
country
```

然后：

```text
TeamSeason
↓
PowerUnitAssignment
↓
PowerUnitManufacturer
```

而不是永久写死：

```text
Team.engine_supplier
```

# 13. Circuit

```text
Circuit

circuit_id

canonical_name
country
city

latitude
longitude

track_length
```

赛道名称发生变化时，不应产生新的 Circuit，除非实际实体需要区分。

# 14. Race / Grand Prix

建议内部使用：

```text
Race
```

代表一个 Grand Prix Event。

```text
race_id

season_id
circuit_id

round

display_name
official_name

scheduled_start
scheduled_end

status

created_at
updated_at
```

# 15. Race Status

Race 状态至少支持：

```text
scheduled
rescheduled
ongoing
completed
cancelled
```

# 16. Session

GrandPrixReminder 不得硬编码：

```text
FP1
FP2
FP3
Qualifying
Race
```

每个 Race 动态拥有：

```text
Session[]
```

Schema：

```text
session_id
race_id

session_type
display_name

scheduled_start
scheduled_end

actual_start
actual_end

status
```

# 17. Session Types

允许：

```text
practice
qualifying
sprint_qualifying
sprint
race
other
```

具体 display name：

```text
FP1
FP2
FP3
Sprint Qualifying
Sprint
Qualifying
Race
```

由数据决定。

# 18. Session Status

```text
scheduled
delayed
started
completed
cancelled
rescheduled
```

Home Reminder 必须根据 Session 当前状态工作。

# 19. Schedule Revision

比赛时间不能简单：

```text
UPDATE session.start_time
```

而不留下任何历史。

重要变更记录：

```text
ScheduleRevision

revision_id
session_id

previous_start
new_start

reason
source

created_at
```

# 20. Notification Dependency

Notification 不永久绑定第一次获取的时间。

正确：

```text
Session
↓
Schedule Update
↓
Notification Recalculation
```

如果比赛：

```text
20:00
↓
21:00
```

系统应重新计算尚未触发的提醒。

# 21. Race Entry

为了表达：

> 某场比赛究竟有哪些车手参加

建立：

```text
RaceEntry
```

Schema：

```text
race_entry_id

race_id
driver_id
team_id

car_number

entry_status
```

# 22. Session Entry

必要时进一步：

```text
SessionEntry
```

解决：

```text
Reserve Driver participates in FP1

↓

Regular Driver returns for qualifying
```

这种情况。

# 23. Qualifying Result

```text
QualifyingResult

session_id
driver_id

position

q1
q2
q3

status
```

# 24. Starting Grid

Starting Grid 与 Qualifying Result 必须分离。

因为：

```text
Qualifying Position
≠
Starting Position
```

Schema：

```text
StartingGrid

race_id
driver_id

qualifying_position
grid_position

penalty_applied
reason
```

# 25. Race Result

```text
RaceResult

race_id
driver_id
team_id

grid_position
finish_position

laps_completed

time
gap

fastest_lap
fastest_lap_time

points

classification_status

result_status
```

# 26. Result Status

至少：

```text
provisional
official
revised
```

# 27. Result Revision

赛后处罚可能改变结果。

不得直接覆盖而不留痕迹。

建立：

```text
ResultRevision

revision_id
race_id
driver_id

previous_position
new_position

previous_points
new_points

reason
decision_source

effective_at
```

# 28. Penalty

建议独立：

```text
Penalty

penalty_id

race_id
session_id
driver_id
team_id

penalty_type
description

effect

issued_at
source
```

可以表达：

```text
Time Penalty
Grid Penalty
Disqualification
Reprimand
Other
```

# 29. Lap Data

Lap：

```text
Lap

lap_id

session_id
driver_id

lap_number
lap_time

sector_1
sector_2
sector_3

position
```

# 30. Tyre Stint

```text
TyreStint

stint_id

session_id
driver_id

compound

start_lap
end_lap

tyre_age_at_start
```

# 31. Pit Stop

```text
PitStop

pit_stop_id

session_id
driver_id

lap
duration

timestamp
```

# 32. Car Model

赛车必须属于具体：

```text
TeamSeason
```

建立：

```text
CarModel

car_model_id

team_season_id

name
season_id

base_3d_model_id
```

# 33. Technical Era

为了支持跨规则时代赛车：

```text
TechnicalEra

technical_era_id

name

valid_from
valid_to

regulation_reference
```

例如不同技术规则周期可以拥有不同 Component Taxonomy。

# 34. Component Taxonomy

赛车部件不能永远写死。

建立：

```text
CarComponentType

component_type_id

technical_era_id

canonical_name
category

parent_component_id

description
```

# 35. 3D Component Mapping

每种部件映射到 Generic 3D Car。

```text
Component3DMapping

component_type_id

model_id
mesh_name

anchor_x
anchor_y
anchor_z

camera_target
```

# 36. Car Specification

一辆赛车在整个赛季并不是一个固定配置。

建立：

```text
CarSpecification

specification_id

car_model_id

race_id
session_id
driver_id

valid_from
valid_to

status
```

允许：

```text
Race Specification
Driver-Specific Specification
Session Test Specification
```

# 37. Upgrade

赛车升级：

```text
Upgrade

upgrade_id

team_season_id
car_model_id

introduced_race_id

component_type_id

title
change_description
technical_goal
expected_effect

status

confidence

created_at
updated_at
```

# 38. Upgrade Lifecycle

Upgrade 不代表：

```text
Introduced
=
Permanent
```

建立：

```text
UpgradeLifecycleEvent

event_id
upgrade_id

race_id
session_id

event_type

timestamp
source
```

event_type：

```text
introduced
tested
retained
modified
removed
reintroduced
superseded
```

# 39. Upgrade Relationships

如果新升级替代旧升级：

```text
UpgradeRelation

upgrade_id
related_upgrade_id

relation_type
```

relation_type：

```text
replaces
modifies
derived_from
tested_against
```

# 40. Driver-Specific Car Specification

必须支持：

```text
Driver A
→ New Floor

Driver B
→ Old Floor
```

因此 Upgrade 不得简单：

```text
Race
+
Team
=
One Specification
```

CarSpecification 可以绑定：

```text
race
session
driver
```

# 41. Evolution Query Model

Evolution 页面主要查询：

```text
Season
↓
TeamSeason
↓
CarModel
↓
Race
↓
CarSpecification
↓
Upgrade[]
↓
Component[]
```

这样可以回答：

```text
What changed?
When?
Where on the car?
Why?
Was it retained?
Which driver used it?
```

# 42. Interview

```text
Interview

interview_id

race_id
session_id

driver_id
team_id_at_time

source_provider
source_url

published_at
retrieved_at

original_text

status
```

# 43. Interview Availability

不得假设每位车手都有采访。

状态：

```text
available
partial
not_available
unverified
```

# 44. Interview Source

同一个采访可能被多个网站转载。

因此建立：

```text
InterviewSource

interview_source_id
interview_id

provider
url

published_at

source_type
```

# 45. Interview Deduplication

Collector 必须尝试识别重复内容。

判断依据：

```text
Driver
Race
Timestamp
Quote Similarity
Text Similarity
Source Relationship
```

不得将同一句采访转载 4 次解释成 4 个独立观点。

# 46. Driver Brief

```text
DriverBrief

driver_brief_id

race_id
driver_id
team_id_at_race

race_assessment
car_strengths
car_weaknesses
strategy
tyres
technical_issues
upgrade_feedback
future_expectations

status

generation_id
```

# 47. Race Brief

```text
RaceBrief

race_brief_id

race_id

technical_themes
team_performance
tyre_issues
strategy_issues
upgrade_feedback
driver_concerns
next_race_expectations

generation_id
```

# 48. AI Generation

所有 AI 输出必须记录生成信息。

```text
AIGeneration

generation_id

provider
model

prompt_version
pipeline_version

generated_at

source_snapshot_id

status
```

# 49. AI Generation Status

```text
pending
generated
validated
rejected
superseded
```

# 50. AI Regeneration

如果：

```text
Model Updated
Prompt Updated
Source Updated
Pipeline Updated
```

允许重新生成 Brief。

但不得直接覆盖旧版本。

正确：

```text
Brief v1
↓
superseded

Brief v2
↓
active
```

# 51. Source Snapshot

AI 必须能够知道：

> 当时究竟基于什么内容生成。

建立：

```text
SourceSnapshot

snapshot_id

created_at
content_hash

source_count
```

并关联：

```text
SourceSnapshotItem
```

保存对应 Interview / Article / Source。

# 52. Data Provenance

重要技术信息必须能够形成：

```text
UI Claim
↓
Driver Brief / Upgrade
↓
Source Snapshot
↓
Interview / Article
↓
Original Source
```

这是 GrandPrixReminder AI 内容可信度的基础。

# 53. Regulation Set

规则也具有版本。

建立：

```text
RegulationSet

regulation_set_id

season_id

sporting_version
technical_version

effective_from
effective_to

source
```

# 54. Scoring Rules

不得假定所有赛季积分规则一致。

建议：

```text
ScoringRule

scoring_rule_id

regulation_set_id

event_type
position
points

valid_from
valid_to
```

但历史官方积分应优先保存官方结果，而不是依靠系统重新计算。

# 55. Provider

统一管理第三方来源：

```text
Provider

provider_id

name
type

base_url

priority
status
```

# 56. Provider Types

例如：

```text
race_data
official_document
interview
team_content
technical_content
```

# 57. Provider Health

建立：

```text
ProviderHealth

provider_id

last_success
last_failure

consecutive_failures

parser_version
schema_version

status
```

# 58. Provider Status

```text
healthy
degraded
unavailable
schema_changed
unknown
```

# 59. Parser Version

网页解析器必须版本化。

例如：

```text
FIAParser

v1
↓
Website changed
↓
v2
```

旧数据必须知道当时由哪个 Parser 解析。

# 60. Raw Data Preservation

对于重要数据源，建议保留：

```text
RawSourceRecord

raw_record_id

provider_id

external_id

retrieved_at

content_hash

raw_payload

parser_version
```

这样 Provider 改版后仍可以重新处理历史数据。

# 61. Data Synchronization

同步分为：

```text
Season Sync
Race Sync
Session Sync
Driver Sync
Team Sync
Result Sync
Interview Sync
Evolution Sync
```

# 62. Season Sync

每个新赛季：

```text
Detect Season
↓
Fetch Entry List
↓
Identity Resolution
↓
Create TeamSeason
↓
Create Driver Assignments
↓
Validate
↓
Season Transition Report
```

# 63. Season Transition Report

必须输出：

```text
New Drivers
Departed Drivers
Transferred Drivers
Replacement Drivers

New Teams
Renamed Teams

Changed Car Numbers
Changed Constructors
Changed PU Suppliers

Unresolved Identities
```

# 64. Race Sync

Race Sync 检查：

```text
New Race
Cancelled Race
Rescheduled Race
Circuit Change
Round Change
```

# 65. Session Sync

Session Sync 检查：

```text
Time Change
Session Added
Session Removed
Session Delayed
Session Cancelled
Format Changed
```

# 66. Result Sync

比赛结束后不能只抓一次。

推荐：

```text
Race Finish
↓
Initial Result
↓
Provisional Result
↓
Official Result
↓
Revision Check
```

直到结果稳定。

# 67. Notification Data Flow

Home Reminder：

```text
Session Provider
↓
Session Sync
↓
Internal Session
↓
Notification Scheduler
```

当：

```text
scheduled_start changes
```

触发：

```text
Notification Recalculation
```

# 68. Briefing Data Flow

```text
Race Completed
↓
Interview Collector
↓
Raw Source
↓
Deduplication
↓
Identity Resolution
↓
Text Cleaning
↓
AI Worker
↓
Driver Brief
↓
Validation
↓
Race Brief
↓
Database
↓
App
```

# 69. Evolution Data Flow

```text
Technical Source
↓
Collector
↓
Team Identification
↓
Component Classification
↓
Upgrade Extraction
↓
Source Validation
↓
Upgrade
↓
Car Specification
↓
3D Component Mapping
↓
Evolution UI
```

# 70. AI Must Not Invent Missing Data

如果无法找到：

```text
Driver Interview
Upgrade Detail
Technical Goal
Driver Feedback
```

必须保存：

```text
unknown
```

或：

```text
not_available
```

禁止：

```text
LLM Guess
```

# 71. Null Is Valid

GrandPrixReminder 数据模型必须接受：

```text
Unknown
Not Published
Not Applicable
Not Available
```

不要为了避免 NULL 而生成假数据。

# 72. Historical Integrity

核心规则：

> Current data must never silently rewrite historical truth.

例如：

```text
Driver transfers to Team B in 2028
```

不得导致：

```text
2027 Race Result
2027 Interview
2027 Briefing
```

显示 Team B。

# 73. Soft Delete

重要历史实体不建议直接物理删除。

推荐：

```text
status = inactive
```

或：

```text
deleted_at
```

避免破坏历史关系。

# 74. Audit Log

关键数据变化建议记录：

```text
AuditLog

entity_type
entity_id

action

previous_value
new_value

source

timestamp
```

# 75. Database Constraints

必须通过数据库约束尽可能阻止：

```text
Duplicate Driver Identity

Duplicate Race Round

Invalid Assignment Period

Upgrade Without TeamSeason

Brief Without Race

Session Without Race
```

# 76. API Read Model

数据库模型不应直接暴露给 Flutter。

Backend 建立：

```text
Database Model
↓
Service
↓
API Schema
↓
Flutter Model
```

这样数据库以后可以变化，而不强制 App 同步重构。

# 77. Home Read Model

例如：

```text
NextRaceResponse

race
circuit

sessions[]

next_session

countdown_target

last_updated
```

# 78. Evolution Read Model

不要让 Flutter 自己组合十几张表。

Backend 返回：

```text
EvolutionResponse

season
team
car

selected_race

specification

upgrades[]

components[]

timeline[]
```

# 79. Briefing Read Model

Backend：

```text
RaceBriefingResponse

race

race_brief

drivers[]

sources[]

generated_at
last_updated
```

# 80. Cache Strategy

数据根据变化频率分类。

### Long Cache

```text
Historical Race
Historical Result
Completed Season
Old Interview
Validated Brief
```

### Medium Cache

```text
Current Season Teams
Current Drivers
Evolution Data
```

### Short Cache

```text
Next Race
Current Weekend
Session Status
Provisional Result
```

# 81. Source Priority

如果多个来源冲突：

```text
Official Source
>
Primary Data Provider
>
Official Team Source
>
Secondary Source
>
AI Inference
```

AI Inference 永远不得覆盖明确的官方事实。

# 82. Conflict Resolution

发生数据冲突时：

```text
Conflict
↓
Compare Source Priority
↓
Compare Timestamp
↓
Compare Confidence
↓
Resolve or Flag
```

无法可靠解决：

```text
Manual Review
```

# 83. Manual Review Queue

建立：

```text
ReviewItem

review_id

entity_type
entity_id

issue_type
description

confidence

status

created_at
resolved_at
```

# 84. Review Types

例如：

```text
driver_identity
team_identity
duplicate_interview
upgrade_classification
technical_claim
source_conflict
result_conflict
```

# 85. Technical Data Confidence

Evolution 数据建议拥有：

```text
confidence
```

例如：

```text
official
confirmed
high
medium
low
```

低可信技术信息不得以确定事实展示。

# 86. 3D Model Independence

3D 模型不得成为赛车技术数据库本身。

正确：

```text
Technical Data
↓
Component
↓
3D Mapping
```

而不是：

```text
3D Mesh Name
=
Database Component Identity
```

这样未来可以替换整个 3D 模型而不修改 Upgrade Database。

# 87. Cross-Era Compatibility

长期支持：

```text
2026
2030
2035
...
```

时，不应假设赛车结构永久不变。

通过：

```text
TechnicalEra
↓
ComponentTaxonomy
↓
3DModel
```

实现不同规则时代适配。

# 88. Data Migration

任何数据库 Schema 修改必须考虑已有历史数据。

禁止：

```text
Change Schema
↓
Delete Database
↓
Reimport Everything
```

作为正式解决方案。

必须使用：

```text
Database Migration
```

# 89. Development Seed Data

开发环境建立独立 Seed Data。

至少覆盖：

```text
Normal Race

Sprint Weekend

Driver Transfer

Mid-Season Replacement

Grid Penalty

Post-Race DSQ

Cancelled Session

Rescheduled Race

Upgrade Introduced

Upgrade Removed

Different Driver Specifications

Missing Interview

Duplicate Interview
```

这些场景必须在开发阶段主动测试。

# 90. Critical Test Scenarios

以下场景属于 GrandPrixReminder 数据架构的强制测试案例：

### Scenario A

```text
Driver transfers between seasons.
```

历史车队保持正确。

### Scenario B

```text
Driver replaced mid-season.
```

不同 Race 显示正确 Driver-Team Relationship。

### Scenario C

```text
Race start delayed by 1 hour.
```

Reminder 自动重新调度。

### Scenario D

```text
Driver qualifies P3 but receives grid penalty.
```

Qualifying = P3。

Starting Grid 显示实际位置。

### Scenario E

```text
Driver finishes P2 but receives post-race DSQ.
```

Result Revision 正确保存。

### Scenario F

```text
Team introduces new floor for Driver A only.
```

Evolution 正确显示双车不同 Specification。

### Scenario G

```text
Upgrade tested in FP1 and removed before Qualifying.
```

Upgrade Lifecycle 正确显示。

### Scenario H

```text
No verified interview exists.
```

Briefing 显示 Not Available。

不得生成 AI 内容。

### Scenario I

```text
Same interview appears on multiple websites.
```

不得重复计入 AI Evidence。

### Scenario J

```text
Provider changes API / HTML structure.
```

系统标记 Provider degraded/schema_changed，而不是静默写入错误数据。

# 91. Architecture Decision Rule

任何新增数据需求，在创建字段之前必须判断：

```text
Is this an Entity?

Is this a Relationship?

Is this a Time-Varying Attribute?

Is this a Version?

Is this an Event?

Is this a Source?

Is this Derived Data?
```

禁止为了快速开发将所有信息不断追加到一个大型 Table。

# 92. Final Data Architecture Principle

GrandPrixReminder 的数据架构必须始终能够回答以下问题：

```text
WHO?
Driver / Team

WHEN?
Season / Race / Session / Valid Time

WHAT?
Result / Interview / Upgrade / Specification

WHY?
Penalty / Technical Goal / Driver Feedback

WHERE?
Circuit / Car Component

SOURCE?
Provider / Original Document

VERSION?
Revision / AI Generation / Regulation / Parser

STATUS?
Scheduled / Official / Tested / Retained / Superseded
```

最终数据链应该能够实现：

```text
External Reality
       ↓
Raw Source
       ↓
Provider
       ↓
Normalizer
       ↓
Identity Resolution
       ↓
Temporal / Versioned Internal Model
       ↓
Validation
       ↓
Database
       ↓
Service
       ↓
API Read Model
       ↓
GrandPrixReminder UI
```

## Final Rule

如果某项数据可能随着：

```text
赛季
比赛
Session
车手
车队
规则
处罚
升级
数据源
AI 模型
```

发生变化：

> 不要默认覆盖旧值。

首先考虑：

```text
Temporal Relationship
Version
Revision
Lifecycle Event
```

GrandPrixReminder 的目标不是只正确显示“现在”。

它必须能够在未来任何时间正确回答：

> **在某一个具体赛季、某一场大奖赛、某一个 Session，当时真实的数据状态是什么？**

这是整个 GrandPrixReminder 历史数据库、AI Briefing、赛事提醒和赛车 Evolution 系统长期可维护的基础。
