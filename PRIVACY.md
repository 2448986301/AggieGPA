# 隐私说明

Aggie GPA 默认完全离线运行。

- 学期、课程、成绩、成绩册、syllabus 识别结果、提醒、规划情景和设置只保存在本机 SwiftData 数据库中。
- 应用没有账号、服务器、CloudKit、Firebase、Supabase、广告、分析追踪、远程日志或崩溃上传服务。
- 应用不主动联网，不收集或上传个人信息与学习记录。
- PDF、图片、扫描件与粘贴的 syllabus 文本只在设备上通过 PDFKit、Vision 和可选的 Foundation Models 处理，不上传，也不使用远程 AI。
- Face ID、Touch ID 或设备密码验证由 iOS 的 LocalAuthentication 完成；应用不会取得或保存生物识别数据。
- Siri 与 Shortcuts 访问默认关闭。App Intents 只提供有限的课程、作业、考试、成绩和 GPA 数据；私密查询要求设备认证，并可在 Settings 中按类别关闭。
- Siri 写操作只生成本机草稿；用户在 Aggie GPA 内明确确认前，不会创建成绩项或修改分数。
- 作业和考试提醒使用 iOS 本地通知，不经过 Aggie GPA 服务器。通知权限被拒绝时，其他成绩册功能仍可使用。
- JSON、CSV 和分享文件由用户自行选择保存位置并负责保管。
- 删除 App 通常会同时删除其本地数据库和本地快照。
- 建议定期导出 JSON backup 到自己信任的位置。

Unofficial student tool. Not affiliated with UC Davis.
