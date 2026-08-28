# Aggie GPA 第一版项目计划

核对日期：2026-07-22

## 产品边界

Aggie GPA 是个人使用、完全离线、非官方的 UC Davis GPA 记录与规划工具。应用不登录、不联网、不追踪、不使用 UC Davis 官方标志，也不对 academic standing 或官方 transcript 作权威判断。

应用内固定免责声明：`Unofficial student tool. Not affiliated with UC Davis.`

## 技术方案

- Swift 6.4、SwiftUI、SwiftData、Charts、LocalAuthentication。
- 最低部署目标 iOS 27.0，iPhone 竖屏优先；界面使用 Xcode 27 SDK 中真实存在的 `glassEffect`、`GlassEffectContainer` 和 Glass button style。
- Decimal 作为 GPA、units、weight、points 的内部数值类型，显示时才舍入。
- 正式记录与 What-If 数据分离；导入先解码、校验和预览，再执行替换或合并。
- 所有资料仅存设备本地；备份使用 JSON 文件，课程表可导出 CSV。
- 无第三方依赖。

## 里程碑

1. 环境与官方规则核对。
2. Xcode 工程、设计系统、SwiftData 数据模型。
3. GPA、Target GPA、Repeat、Final Grade 计算引擎及单元测试。
4. Onboarding、Dashboard、Quarters、Course Editor。
5. Planner、情景比较、未来季度规划。
6. JSON/CSV、快照、Face ID、Settings。
7. 三个图标方向、分层 SVG、正式图标与预览。
8. 编译、单元测试、UI 测试、模拟器视觉与无障碍检查。
9. 真机免费签名安装（已完成：Personal Team 签名、安装、启动和进程验证）。
10. 文档与最终交付核验。

## 已知环境状态

- 工作目录：`/Users/easonzhou/Documents/UCD`
- Xcode：27.0 beta（27A5228h），位于 `/Applications/Xcode-beta.app`
- Swift：6.4
- iOS / iOS Simulator SDK：27.0
- Icon Composer：已随 Xcode 安装
- iOS 27.0 Simulator Runtime 已安装；iPhone 17 Pro 与 iPhone 17e 均已实际运行和截图。
- 最终 clean build、39 个单元测试和 10 个 UI 测试已通过。
- 真机免费签名安装已在连接的 iOS 27 iPhone 上完成；iPhone Mirroring 的逐页视觉检查仍需手机锁定后连接。
