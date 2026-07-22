# 测试说明

## 命令

本机 Xcode 位于 `/Applications/Xcode-beta.app`，所以命令行使用：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project AggieGPA.xcodeproj -scheme AggieGPA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

如果设备名不同，可先执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl list devices available
```

## 覆盖范围

- 83 个单元测试：v1 原地迁移、migration backup、课程成绩 Decimal engine、weighted/points/hybrid、missing/drop/extra credit、forecast、Projected GPA 隔离、syllabus parser、Foundation Models fallback、通知 scheduling、App Intents 隐私与 draft、JSON v1/v2、实际 replace import、CSV、隐私锁和 v1.0 回归。
- 13 个 UI 测试：onboarding、季度、课程、删除/Undo、What-If、导出、Settings、Dark appearance、privacy lock、打开 Gradebook、syllabus 识别与确认入口、Siri 默认关闭和最大辅助字体。
- UI tests 使用 `--uitest-in-memory`，不会污染真实本地数据。

## 状态记录

- 2026-07-22：iOS 27.0 Simulator Runtime（24A5390f）安装完成。
- 2026-07-22：iPhone 17 Pro 上 `clean build` 通过。
- 2026-07-22：41/41 Unit Tests 通过，0 failed、0 skipped、0 runtime warnings。
- 2026-07-22：10/10 UI Tests 通过，0 failed、0 skipped；最后完整结果包运行时警告为 0。
- 2026-07-22：额外单独回归“添加课程 + 数字键盘 + Done”，通过且 runtime warnings 为 0。
- 2026-07-22：在 Xcode GUI 中选择 iPhone 17e，Run 状态显示 `Running AggieGPA on iPhone 17e`；首次 onboarding 已实际截图。
- 2026-07-22：Xcode 已识别 `Eason’s iPhone (iOS 27.0)`，Developer Mode 已开启，并使用 `yichen zhou (Personal Team)` 完成免费签名。
- 2026-07-22：真机 arm64 build 成功；`com.easonzhou.aggiegpa` 已安装并成功启动，随后通过设备进程列表确认 AggieGPA 正在运行。
- 2026-07-22：v1.1 iPhone 17 Pro Simulator 全部 83/83 Unit Tests 通过；12 个 backup/data-safety tests 包括 v1 兼容和 v2 关系恢复。
- 2026-07-22：v1.1 UI 新增 syllabus、Siri 默认关闭和 Accessibility XXXL 流程均单独通过；最终完整 13-test 串行结果记录在本文件最后一次更新时的 xcresult。
- 2026-07-22：iPhone Mirroring 可用，但本次检查时显示“iPhone in Use”；需锁定 iPhone 后才能继续镜像视觉检查，因此未伪称已经完成镜像内逐页检查。
- Xcode 27 beta 偶尔在测试结束后的诊断收集阶段报告 `simctl` 路径提示；这不是应用或测试失败，`xcresulttool` 的最终结果为 Passed。

## 手工视觉矩阵

已截图核对：Light、Dark、iPhone 17 Pro、iPhone 17e、英文、简体中文、Dashboard、Quarters、Planner、Settings、demo data。Dynamic Type、Reduce Motion、Reduce Transparency、全 P/NP、长课程名、GPA 0/4.0、导入错误和 Face ID unavailable 由 Preview、逻辑分支或自动测试覆盖。真机已检查 App Icon，并用“立即”隐私锁完成前后台复测；验证后持续观察未出现重复 Face ID 请求。
