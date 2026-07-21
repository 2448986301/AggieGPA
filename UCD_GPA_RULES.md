# UC Davis GPA 规则核对

核对日期：2026-07-21

Aggie GPA 是估算工具，以下规则用于计算引擎，不代表 Registrar 对某位学生记录的最终决定。

## 官方来源

1. UC Davis General Catalog — [Grades & Grading](https://catalog.ucdavis.edu/academic-information-policies-regulations/grades-grading/)
2. UC Davis Office of the University Registrar — [Grades & Grading](https://registrar.ucdavis.edu/records/grades)
3. UC Davis Office of the University Registrar — [Repeat Notations](https://registrar.ucdavis.edu/faculty-staff/itg/repeat)
4. UC Davis Office of the University Registrar — [Transfer Credit](https://registrar.ucdavis.edu/records/transfer-credit)
5. UC Davis Office of the University Registrar — [End-of-Transcript](https://registrar.ucdavis.edu/faculty-staff/itg/end-of-transcript)

## 实际采用的规则

### 字母成绩点

| Grade | Points | Grade | Points |
|---|---:|---|---:|
| A+ | 4.0 | C+ | 2.3 |
| A | 4.0 | C | 2.0 |
| A- | 3.7 | C- | 1.7 |
| B+ | 3.3 | D+ | 1.3 |
| B | 3.0 | D | 1.0 |
| B- | 2.7 | D- | 0.7 |
|  |  | F | 0.0 |

A+ 与 A 相同，都是 4.0，不使用 4.3。

每门课 grade points = units × grade-point value；GPA = 总 grade points ÷ 总 attempted GPA units。内部使用 `Decimal`，中间结果不舍入，只有显示时按设置保留 2、3 或 4 位小数。

### 不进入 GPA 的 notation

P、NP、S、U、I、IP、NG 默认不进入 GPA 分子和分母。Incomplete、In Progress 和 No Grade 可能在官方记录中后来改变；应用不会预测 Registrar 的最终处理。

### 课程来源

- UC Davis：默认进入 UC GPA（仍须是可计 GPA 的字母成绩课程）。
- Other UC Campus：官方说明中，可转入的其他 UC 课程可能进入 UC GPA，应用默认允许计入，但应以 transcript 为准。
- Community College、其他非 UC 学校、AP/IB/A-Level、高中学分：默认排除 GPA。
- 用户可以为个人规划手动开启 Include in GPA，但界面会显示警告。

### 本科重复课程估算

- 允许在规则适用时替换最多 16 units。
- 在上限以内，原尝试从 GPA attempted units 和 grade points 中排除，最近一次尝试计入。
- 达到 16 units 之后，新旧尝试都计入。
- 如果某一门重复课的 units 会“部分超过”16-unit 上限，不拆分 units；该课程新旧两次都计入。
- 多次重复、units 不一致、P/NP 与字母成绩混合、缺少关联或用户标记 Manual Review 的情况不会静默决定，会要求人工核对。
- 规则还限制哪些原成绩可以合法重复，并可能受 ELWR、先修课、学院和研究生规则影响。本应用不判断重复资格。

## 与需求暂定规则的差异或补充

- 暂定的 16-unit 替换方向与 2026-2027 官方页面一致。
- 官方信息特别明确：若一门课只会部分超出 16-unit 上限，则该门课的新旧成绩都计入，而不是只替换剩余 units。引擎按此实现。
- 官方 UC GPA 可以包含其他 UC 校区的可转入课程；非 UC 转学课程通常不进入 UC GPA。应用因此把 “Other UC Campus” 与一般 “Transfer Credit” 分开处理。

## 必须人工核对的情况

学院或专业 GPA 定义、ELWR 重复门槛、研究生规则、非法重复、课程 credit 限制、units 调整、ENWS、已永久化的 I、转学认定、academic standing、毕业资格和官方 transcript annotation 都必须查看正式记录或咨询 advisor。

