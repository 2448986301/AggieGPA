# Changelog

## [1.3.0] — Unreleased

### Added

- Rebuilt syllabus import around Apple Foundation Models on supported devices. It
  reads native PDF text or analyzes scanned pages as images; it does not use OCR.
- Added reviewable grading categories, weights, assessments, dates, special rules,
  page evidence, confidence indicators, and explicit review flags.

### Improved

- Import results stay editable and no course data changes until Confirm Import.
- Improved English and Simplified Chinese syllabus-import status, privacy, review,
  warning, and error guidance.

### Notes

- On-device model availability depends on the device, enabled Apple Intelligence,
  language, and downloaded system model. Private Cloud Compute is not a released
  feature claim: it remains gated by Apple entitlement, availability, and a
  separate in-app permission.

## [1.2.0] — Unreleased

### Changed

- Unified the iPhone app around a calmer Apple-inspired design system: consistent
  color, typography, spacing, corner radii, and SF Symbols.
- Reworked Today, Courses, Course Detail, assignment/exam/score entry, and GPA
  hierarchy so current work and official versus estimated results are easier to scan.
- Limited Liquid Glass to navigation, summaries, and key actions; regular lists,
  forms, and reading surfaces stay lightweight and legible.

### Improved

- Simplified Settings around student tasks and improved syllabus-import, backup,
  What-If, Siri-draft, empty, loading, success, and error feedback.
- Added an in-app What’s New experience and version history in Settings > About.
- Improved English and Simplified Chinese release-note layouts, Dynamic Type,
  VoiceOver labels, Reduce Motion behavior, and light/dark contrast.

### Fixed

- Corrected navigation, layout alignment, long-label handling, grade-category
  selection, and layered Liquid Glass issues found during the design pass.

## [1.1.2] — Documented development version

### Added

- Optional, privacy-controlled Siri access for GPA data and confirmed drafts before
  Siri can write a grade.
- Course Spotlight indexing and bilingual Siri guidance.

### Notes

- One exact assignment-summary App Shortcut phrase and Spotlight indexing have
  documented device evidence. Natural-language, Chinese Siri, native search/open,
  and other Siri routes remain unverified and are not release claims.

## [1.1.1] — Documented development checkpoint

- Student-first Today page, global Add entry point, and simpler course-detail flow.
- Easier first-term setup, direct score entry, current course-grade updates, and
  clearer grade-breakdown and target-grade guidance.
- Expanded visible English and Simplified Chinese copy; ungraded work remains
  excluded from current-grade calculations.

## [1.1.0] — Documented development version

- 在现有课程详情中加入本机成绩册：类别权重、作业/考试、earned/possible points、drop lowest、extra credit、缺交策略与成绩分界。
- 分离正式成绩、当前计算成绩、预测总评与 Projected GPA；预测不会改写正式记录。
- 加入多个本地 Forecast Scenario、目标成绩与期末所需成绩计算。
- 支持从 PDF、图片、相机扫描或粘贴文字提取 syllabus 评分规则；所有结果必须人工核对并确认后才保存。
- 可选使用 iOS 端侧 Foundation Models 优化识别；不可用时自动退回确定性本地解析，不使用远程 AI。
- 加入作业和考试的本地通知，修改截止时间会更新提醒，删除项目会取消提醒。
- 加入 App Intents、App Shortcuts 和中英文短语；Siri 默认关闭，私密查询需要设备认证，写操作只创建待确认草稿。
- SwiftData 升级为 versioned schema，并在迁移前创建可验证的 v1 JSON 恢复备份。
- JSON backup 升级到 schema v2，包含成绩册、提醒、预测和 Siri 设置，同时继续读取 v1 backup。
- 扩充简体中文、VoiceOver、最大辅助字体和 Reduce Motion 覆盖。
- 当时的测试记录覆盖计算、迁移、备份、解析、通知、Intents、隐私和关键界面流程。

## [1.0] — Documented baseline

- 创建 SwiftUI + SwiftData 离线 iOS 27 应用。
- 加入 Dashboard、季度和课程管理、GPA 图表。
- 加入 What-If、Target GPA、Final Grade、Scenario 和 Future Quarter Planner。
- 加入本科 16-unit repeat 估算与 manual review。
- 加入 JSON import/export、CSV、ShareLink 和最多 5 个本地快照。
- 加入 LocalAuthentication 隐私锁、Light/Dark 和无障碍 fallback。
- 加入跟随系统、English 与简体中文的应用内即时语言切换。
- 创建三套原创 Liquid Glass 图标方向、第二轮正式方案和完整分层 SVG。
- 添加 41 个 unit tests 与 10 个 UI tests。
- 修复 App Icon 未绑定到 target 导致真机图标缺失的问题。
- 修复“立即”隐私锁在 Face ID 完成后因 scene 再次 active 而循环验证的问题。
- 在 iOS 27 iPhone 17 Pro 和 iPhone 17e 模拟器完成构建、测试与视觉截图。
- 使用免费 Personal Team 在 iOS 27 真机完成签名、安装、启动和运行进程验证。
