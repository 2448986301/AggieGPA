# 使用 Siri 操作 Aggie GPA

最后更新：2026-07-23

## 目前已验证的功能

在测试用的 iPhone 17 Pro（iOS 27 测试版）上，下面这句英文指令已经通过真机验证：

> View assignments in Aggie GPA

Siri 会显示 Aggie GPA 卡片，列出未来七天内到期的作业。真机测试中，卡片正确显示了 `CHE 002A` 的 `Homework 3` 和截止日期。

你不需要打开“快捷指令”App，也不需要手动创建快捷指令。Aggie GPA 会自动注册这句话。不过，iOS 仍可能显示“正在运行快捷指令”一类系统文字，这是系统对自动 App Shortcut 路径的称呼，并不代表用户手动创建过快捷指令。

## 设置方法

1. 安装或更新后，先打开一次 Aggie GPA。
2. 进入 Aggie GPA → 设置 → Siri AI。
3. 打开“启用 Siri 访问”。
4. 如果需要使用已验证的作业查询，再打开“允许作业摘要”。
5. 如果希望课程出现在系统搜索中，请在 iOS 设置的 Aggie GPA 页面允许 Siri/Apple Intelligence 学习以及显示 App 内容。
6. 确认 Siri 已启用，并且 Siri 语言与所说的指令一致。

详细成绩、GPA 回答和创建草稿分别有独立开关，因为这些内容更敏感。不希望 Siri 访问的类别可以继续关闭。

## 正常结果

使用已验证的指令后，Siri 应显示带有 Aggie GPA 名称的卡片，其中包括作业名称、课程代码和截止日期。如果未来七天没有作业，Aggie GPA 应在意图真正运行后给出明确的空结果。

如果 Siri 直接说“找不到作业”或“无法在 Aggie GPA 内搜索”，这可能只是系统回退回答，并不能证明 Aggie GPA 查询结果为空。

## 搜索和打开课程的现状

Aggie GPA 已把课程加入 iOS 搜索索引。真机在 Spotlight 中搜索 `CHE 002A` 时，已经显示真实课程结果。

但在当前测试的 iOS 27 测试版中，`Search Aggie GPA for CHE 002A` 和 `Open CHE 002A in Aggie GPA` 还没有触发 App 内原生搜索/打开代码。在后续真机测试通过前，不能宣称这两条纯 App Schema 路径已经可用。

## 隐私说明

- 作业摘要来自设备本地的小型快照，只在 Aggie GPA 已签名的进程之间共享。
- 课程和作业的发现信息可能显示在 iOS 系统搜索中。
- 详细成绩和 GPA 需要单独授权，并要求本机身份验证。
- Siri 的写入类请求只会先生成草稿；必须回到 Aggie GPA 确认后才会保存。
- 预测成绩永远不会覆盖官方成绩。

## 排查方法

- 先使用上面已验证的精确英文指令。
- 打开一次 Aggie GPA，稍等片刻，让 App 更新 Siri 注册和搜索索引。
- 检查 Aggie GPA 的 Siri AI 开关，以及 iOS 中的 Siri 和搜索权限。
- 如果 Siri 报告网络连接问题，请检查网络或 VPN；成功测试时 VPN 处于关闭状态。
- 更新 App 或 iOS 测试版后，可重启 iPhone，再打开 Aggie GPA 后重试。
- 不要为了刷新 Siri 而删除 App；应使用覆盖更新，以保留已有课程、成绩、偏好、方案和备份。

当前 iOS 27 SDK 没有教育、成绩或 GPA 的系统 App Schema，因此更广泛的成绩和 GPA 功能只能使用准确命名的 Aggie GPA 自定义意图，不能伪装成系统教育领域。
