# Aggie GPA

**Unofficial GPA Planner for UC Davis Students**

Aggie GPA 是一个供 UC Davis 学生个人使用的非官方、完全离线的 iPhone GPA 记录、课程成绩册与规划工具。v1.1 可以记录 category、作业、考试和分数，计算 Current Grade、Forecast 与 Projected GPA，并从 syllabus 提取待确认的评分规则。它没有账号、服务器或远程 AI。

> Unofficial student tool. Not affiliated with UC Davis.

它不是 UC Davis 开发、授权或运营的软件，不会代替官方 transcript、OASIS、Registrar 或 academic advisor。

## 当前版本包含什么

- SwiftData 本机课程、quarter、scenario、grading plan 和偏好设置。
- 每门课的 Gradebook、category weights、作业/考试、提醒、drop lowest、extra credit 和可编辑分数线。
- Official GPA、Current Grade、Projected Grade 与 Projected GPA 明确分开，预测绝不改写正式记录。
- PDF、图片、相机或粘贴文字的本机 syllabus 识别；保存前必须人工确认。
- 可选端侧 Foundation Models；不可用时退回本地规则解析。
- Siri / Shortcuts 查询与草稿操作，默认关闭并按数据类别授权。
- Decimal 精确 GPA engine；A+ = 4.0，中间结果不提前舍入。
- Dashboard Hero、当前/专业/upper-division GPA、课程概览和 Charts 趋势。
- Quarter 新建、复制、排序、搜索、按学年筛选；课程添加、编辑、复制、删除和 Undo。
- What-If 与正式记录隔离；明确确认后才能 Save to Records。
- Target GPA、Final Grade、Scenario Comparison、Future Quarter Planner。
- UC Davis 本科 16-unit repeat replacement 估算和 manual-review 警告。
- JSON export/import（Replace / Merge / Cancel）、CSV、Share Sheet 和最近 5 个本地快照。
- Face ID / Touch ID / passcode、立即/1 分钟/5 分钟锁定。
- Light、Dark、Dynamic Type、VoiceOver、Reduce Motion 和 Reduce Transparency fallback。
- 应用内支持“跟随系统 / English / 简体中文”即时切换；课程代码和用户录入内容保持原样。
- iOS 27 原生 `glassEffect` / Glass button style；长列表和表单不过度玻璃化。
- 三套原创图标候选、第二轮正式方案、6 个独立 SVG 图层与系统模式预览。
- 83 个 Unit Tests 和 13 个 UI Tests。

## 开发环境

- Xcode 27.0 beta 4（27A5228h）
- Swift 6.4
- iOS 27.0 SDK / iOS Simulator 27.0 SDK
- Bundle Identifier：`com.easonzhou.aggiegpa`
- 第三方依赖：无

Xcode 27 SDK 实际提供的 API 名称是 `glassEffect(_:in:)`、`GlassEffectContainer`、`Glass.regular/clear/tint/interactive`、`.buttonStyle(.glass/.glassProminent)`。项目使用这些真实接口，没有编造 SwiftUI API。

## 如何打开和运行

1. 在 Finder 打开本文件夹。
2. 双击 `AggieGPA.xcodeproj`。
3. 在 Xcode 顶部设备菜单选择一个 iOS 27 iPhone simulator，例如 iPhone 17 Pro。
4. 点击左上角 Run（三角形），或按 `⌘R`。
5. 第一次启动会出现三页 onboarding。Demo Data 是可选且明确标记的虚构数据。

完成 onboarding 后，可在 Settings > Display > Language（设置 > 显示 > 语言）随时选择跟随系统、English 或简体中文，无需重启，也不会改变任何 GPA 数据。

如果 Xcode 提示 simulator runtime 尚未安装：打开 Xcode > Settings > Components，在 iOS 27 Simulator 旁点击 Download。

## 安装到自己的 iPhone（免费 Personal Team）

不需要购买 Apple Developer Program。

1. 用数据线或已配对的 Wi-Fi 连接 iPhone，并在手机上点“信任”。
2. Xcode > Settings > Accounts，点击左下角 `+`，选择 Apple Account；账号和密码请本人输入，Codex 不读取。
3. 在左侧 Project Navigator 选择蓝色 `AggieGPA` project，再选择 TARGETS > AggieGPA > Signing & Capabilities。
4. 勾选 Automatically manage signing，在 Team 选择你的 **Personal Team**。
5. 如果 `com.easonzhou.aggiegpa` 已被占用，把 Bundle Identifier 改成只属于你的值，例如 `com.你的名字.aggiegpa`。
6. 在 Xcode 顶部运行设备菜单选择已连接的 iPhone，按 `⌘R`。
7. 若手机要求 Developer Mode：Settings > Privacy & Security > Developer Mode > On，按提示重启并在重启后确认。
8. 第一次打开免费签名 App 时，如 iOS 要求信任开发者：Settings > General > VPN & Device Management > Developer App，选择对应 Apple Account 并点 Trust。
8. 若手机提示开发者不受信任：Settings > General > VPN & Device Management，选择你的 Apple Account 对应开发者并点 Trust（只有系统确实显示时才做）。

免费 Personal Team 签名通常有较短有效期；到期后把 iPhone 重新连接 Xcode，再次选择同一 Team 并按 `⌘R` 重新安装/签名即可。本项目不会上传 App Store Connect，也不会创建付费证书。

## 使用方法

### 录入成绩

在 Quarters 点 `+` 新建 quarter，进入它后再点 `+` 添加课程。快速添加只需要 Course Code、Units 和 Grade。非 UC、AP/IB 或一般 transfer work 默认不应进入 UC GPA；若手动打开 Include in GPA，应用会显示警告。

### What-If

Planner > What-If GPA。修改这里的 grade 不会修改正式记录。Save Scenario 只保存情景；Save to Records 会先显示明确确认。

### Target GPA

Planner > Target GPA Calculator，可自动使用本机记录，也可以手动输入 current GPA、current units、target 和 future units。结果显示需要的未来平均、数学可达性和最高可能 GPA。

### Final Grade

Planner > Final Grade Calculator。按 syllabus 输入 category weight、earned / possible points 和 final weight。应用不会假装存在统一的“UC Davis 官方百分比边界”。权重不为 100% 时结果会标记 partial setup。

### Gradebook、作业和权重

进入 Quarters，打开已有 quarter，再点一门课程。右上角菜单可先设置 Grading Policy，然后添加 Category 和 Grade Item。Category 可填写 Homework、Quiz、Midterm、Final 等名称和权重；Grade Item 可填写 earned / possible points、截止时间、状态、extra credit、excused、dropped 与提醒。

未评分项目默认不按 0 分处理。若确实要把 missing work 算作 0，必须在 Grading Policy 中选择并再次确认。Current Grade 只反映你录入的规则和分数，不是 Registrar 的正式成绩。

### 导入 syllabus

课程右上角 > Import Grading Policy，可选择 PDF 或图片、使用相机扫描，或直接粘贴 grading rules。Aggie GPA 会显示识别原文、置信度、category 和需要人工核对的问题。只有点 Confirm and Save Rules 后才会写入；已有 category 时不会静默覆盖。

支持 Apple Intelligence 的设备可选择 Refine with On-Device Model。模型不可用、未下载或不支持当前语言时，本地确定性 parser 仍可工作；syllabus 不会上传，也不会调用远程 AI。

### Forecast、Official 与 Projected

Official GPA 只使用课程正式记录中的 letter grade。Gradebook 的 Current Grade 是当前已录入任务的计算值；Forecast 是对剩余任务的情景估算；Dashboard 的 Projected GPA 只对尚无正式成绩的课程使用已选择 forecast。任何预测都不会修改 Official GPA。

### 通知

在 Grade Item 中设置截止时间并打开 Remind me，保存时 iOS 才会请求通知权限。可选择提前 1 天、3 天、1 周或自定义时间。修改截止时间会替换原提醒，删除项目会取消提醒。Settings > Assignment & Exam Reminders 可查看或请求权限。

### Siri 与快捷指令

Settings > Siri & Shortcuts Access 中先打开总开关，再单独允许作业摘要、详细分数、GPA 回答或草稿。私密查询需要本机身份验证。可以在 Siri 或 Shortcuts 中使用类似“查看 Aggie GPA 本周作业”“查询 Aggie GPA 课程成绩”“查询 Aggie GPA 累计 GPA”“在 Aggie GPA 添加作业草稿”的指令。草稿必须回到 App 内确认后才保存。

## 备份、恢复和 CSV

Settings > Import, Export & Backups：

- Export JSON Backup：保存完整可恢复备份。
- Share latest JSON backup：打开系统 Share Sheet。
- Import JSON Backup：先验证 schema 和内容，再显示预览；可 Merge、Replace 或 Cancel。v2 包含成绩册、提醒、forecast 与 Siri 设置，仍可读取 v1 backup。
- Export CSV：导出适合表格软件查看的课程明细。
- 导入和 Reset 之前自动创建本地快照，最多保留 5 个。

导出文件由你自行保管。示例位于 `Documentation/Samples`。

## 数据保存在哪里

正式数据位于 iOS 为 Aggie GPA 分配的 app sandbox 中，由 SwiftData 管理；本地 snapshot 位于该 sandbox 的 Application Support/AggieGPA/Snapshots。应用不使用 CloudKit 或服务器。

删除 App 通常会删除本地 SwiftData 数据库与本地 snapshots。删除前请 Export JSON Backup。

## 从 v1.0 原地升级

v1.1 保持 `com.easonzhou.aggiegpa`、原 App 名称和同一 Signing Team，版本为 1.1.0（build 2）。使用 Xcode 选择原来安装 v1.0 的同一 iPhone 后直接 Run，不要卸载、删除 App 或清空数据。首次打开前会尝试创建可验证的 v1 JSON migration backup，再由 versioned SwiftData schema 进行轻量迁移。

升级后先确认原 quarters、courses、正式 grades、GPA 和设置仍存在，再试用 Gradebook。若免费 Personal Team 签名到期，只需使用同一 Team 和 Bundle Identifier 重新 Build and Run；不要删除旧 App。

## 修改应用名称或 Bundle Identifier

- 名称：Target > General > Display Name；当前是 Aggie GPA。
- Bundle Identifier：Target > Signing & Capabilities > Bundle Identifier。
- 修改 identifier 后，iOS 会把它视作另一个 App，旧 App 的本地数据不会自动迁移；请先导出 JSON。

## 更换图标与 Icon Composer

当前可编译 icon 位于 `AggieGPA/Resources/Assets.xcassets/AppIcon.appiconset`。正式设计、候选、PNG、SVG 图层、小尺寸测试与主屏幕预览位于 `Documentation/Icon`。

iOS Home Screen 的 Default、Dark、Clear、Tinted 和 Monochrome 是系统外观模式，不是应用内可随意伪造的 runtime theme。项目在 Settings 中明确显示“Managed by iOS”。

完整 Icon Composer 导入顺序、material、depth、refraction、highlight 和 shadow 设置见 `ICON_SETUP.md`。

## 如何运行测试

在 Xcode 按 `⌘U`。命令行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project AggieGPA.xcodeproj -scheme AggieGPA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

如设备名不同，用 `xcrun simctl list devices available` 查看。详细覆盖范围与真实执行状态见 `TESTING.md`。

## GPA 规则与为什么只能估算

规则来源、核对日期和实现差异见 `UCD_GPA_RULES.md`。主要来源是 UC Davis General Catalog、Office of the University Registrar Grades & Grading、Repeat Notations、Transfer Credit 和 End-of-Transcript。

以下情况必须查看正式 transcript 或咨询 advisor：

- 多次或非法 repeat、units 不一致、P/NP 与 letter grade 混合。
- ELWR、学院/专业/研究生或课程特定的 repeat 限制。
- AP/IB/A-Level、community college、其他 UC 和 transfer articulation。
- Major GPA 的具体课程集合、graduation eligibility、academic standing。
- I、IP、NG、ENWS、课程 credit restriction、units adjustment。

Aggie GPA 不会直接宣称 Good Standing、Probation、Subject to Dismissal 或 Graduation Eligible。

## 已知限制

- 没有服务器和设备间自动同步；备份依赖手动 JSON export。
- syllabus OCR 和规则识别可能不完整，曲线、替代考试和复杂 extra credit 必须人工核对。
- Foundation Models、Siri、Shortcuts 和通知的实际可用性取决于设备、语言、已下载模型、系统权限与 Personal Team 配置。
- Siri 只提供有限本机数据；写操作只能创建待确认草稿。
- Major / upper-division 标记由用户维护，应用不知道某个专业的官方 course list。
- Repeat 只对安全的简单情况自动估算，复杂情况刻意要求人工核对。
- 系统 icon appearance 由 iOS 管理；不是所有 appearance 都能由免费签名 App 在运行时切换。
- 真机安装、Apple Account 登录、Personal Team、Developer Mode 和系统权限必须由设备所有者本人确认。
- iPhone Mirroring 只能用于安装后的检查，不能代替 Xcode 安装。
- Xcode 27 当前为 beta；命令行 UI 测试结束时可能输出一次诊断收集工具路径提示，但最终 `.xcresult` 中 10 个测试均通过且应用运行时警告为 0。

## 已完成的模拟器检查

- iOS 27.0 iPhone 17 Pro：浅色、深色、英文、简体中文、Dashboard、Quarters、Planner、Settings。
- iOS 27.0 iPhone 17e：较小屏幕 Dashboard。
- 实际截图位于 `Documentation/Screenshots`，均来自当前项目在 Simulator 中运行后的 `simctl` 截图，不是设计稿。
- 项目已在 Xcode GUI 中打开并通过 Run 运行到 iPhone 17e；`xcode_run_onboarding_iphone17e.png` 是该次运行的首次启动画面。
- 项目也已使用免费 Personal Team 在连接的 iOS 27 真机成功编译、安装和启动；设备进程列表确认 `com.easonzhou.aggiegpa` 正在运行。

## 其他文档

- `PROJECT_PLAN.md` — 目标、技术方案与里程碑
- `ARCHITECTURE.md` — 代码结构和关键决定
- `TESTING.md` — 测试覆盖与执行状态
- `UCD_GPA_RULES.md` — 官方规则核对
- `PRIVACY.md` — 本地数据与隐私
- `ICON_SETUP.md` — Liquid Glass 图标导入
- `CHANGELOG.md` — 版本记录
