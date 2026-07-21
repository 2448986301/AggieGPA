# 架构说明

## 技术栈

Swift 6.4、SwiftUI、SwiftData、Charts、LocalAuthentication、UniformTypeIdentifiers、FileDocument 和 XCTest。项目没有第三方依赖。

## 目录

- `App`：应用入口、根导航、Tab 与隐私锁遮罩。
- `Models`：SwiftData entities 与 raw-value domain enums。
- `Services`：纯计算服务、重复课程引擎、隐私锁和本地快照。
- `ImportExport`：可版本化 JSON DTO、校验、merge/replace 与 CSV。
- `Features`：Dashboard、Quarters、Planner、Settings、Onboarding。
- `DesignSystem`：颜色、间距、圆角、motion、glass card fallback。
- `PreviewContent`：与真实用户数据区分的 demo data。
- `AggieGPATests` / `AggieGPAUITests`：单元与 UI 测试。

## 关键决定

- `CourseGrade.gradePointValue` 是唯一成绩点映射来源。
- 所有 GPA 计算都经过 `GPAService`，What-If 与正式记录复用同一引擎。
- `RepeatCourseEngine` 只自动处理安全的两次、同 units、字母成绩重复；复杂情况转为 manual review。
- `TargetGPAService` 和 `FinalGradeService` 是纯函数，便于测试。
- JSON 先完整 decode 与 schema validation，再 preview；执行导入前创建快照。
- `Decimal` 用于 GPA、units、weight 与 points；只在 UI 格式化时舍入。
- iOS 27 原生 `glassEffect` 只用于 Hero、工具栏按钮、锁定和 Undo 等层级重点，长表单与列表保持实体背景。
- Reduce Transparency 时 `glassCard` 自动退回高可读的系统 grouped background。

## 数据安全

SwiftData 写入失败不会显示底层错误或堆栈。导入先验证，文件写入使用 atomic option，Replace 在成功解码并创建快照后执行。

