# 数据库表结构设计 + AI修复指令

## 一、数据库表结构

### sport_record（运动记录表）

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | 记录ID |
| sport_name | TEXT | NOT NULL | 运动名称（跑步/游泳/骑行等） |
| duration | INTEGER | NOT NULL | 运动时长（分钟） |
| calories | INTEGER | NOT NULL | 消耗卡路里 |
| sport_date | TEXT | NOT NULL | 运动日期（YYYY-MM-DD） |
| create_time | TEXT | NOT NULL | 创建记录时间 |

### SQL 建表语句

```sql
CREATE TABLE IF NOT EXISTS sport_record (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sport_name TEXT NOT NULL,
  duration INTEGER NOT NULL,
  calories INTEGER NOT NULL,
  sport_date TEXT NOT NULL,
  create_time TEXT NOT NULL
);
```

---

## 二、数据模型接口（已更新）

```typescript
// 运动记录数据模型 - 与 sport_record 表字段一一对应
interface SportRecord {
  id: number
  sport_name: string      // 对应 sport_name
  duration: number        // 对应 duration
  calories: number        // 对应 calories
  sport_date: string      // 对应 sport_date (YYYY-MM-DD)
  create_time: string     // 对应 create_time
}
```

---

## 三、需要AI修改的内容

### 修改文件清单

1. `entry/src/main/ets/data/SportDataManager.ets` - 数据库管理类（已完成重写）
2. `entry/src/main/ets/pages/Index.ets` - 页面代码（需同步修改字段名）
3. `entry/src/main/ets/entryability/EntryAbility.ets` - 初始化数据库（需补充）

---

## 四、给AI的修复指令

```
请根据以下数据库表结构修改项目代码：

【数据库表结构】
表名：sport_record
字段：
- id: INTEGER PRIMARY KEY AUTOINCREMENT
- sport_name: TEXT NOT NULL (运动名称)
- duration: INTEGER NOT NULL (运动时长/分钟)
- calories: INTEGER NOT NULL (消耗卡路里)
- sport_date: TEXT NOT NULL (运动日期 YYYY-MM-DD)
- create_time: TEXT NOT NULL (创建时间)

【需要修改的文件】

1. entry/src/main/ets/data/SportDataManager.ets
   - 已将 preferences 替换为 relationalStore 数据库存储
   - SportRecord 接口字段已更新为：sport_name, sport_date, create_time
   - 确保所有方法使用新的字段名

2. entry/src/main/ets/pages/Index.ets
   - 修改所有使用 record.name 的地方为 record.sport_name
   - 修改所有使用 record.date 的地方为 record.sport_date
   - 修改所有使用 record.type 的地方（删除或替换为 sport_name）
   - 修改 loadRecords() 中的模拟数据，使用新字段名
   - 修改 AddRecordDialog 中保存记录的逻辑，使用新字段名

3. entry/src/main/ets/entryability/EntryAbility.ets
   - 在 onCreate 中初始化 SportDataManager：
     await SportDataManager.getInstance().init(this.context)

【字段映射对照表】
旧字段名 -> 新字段名
name -> sport_name
date -> sport_date
type -> 删除，使用 sport_name 代替
（新增）create_time -> 自动填充

【注意事项】
- ArkTS 强类型要求：所有对象字面量必须显式声明接口类型
- 颜色硬编码警告：使用 $r('app.color.xxx') 替代 '#4CAF50' 等硬编码颜色
- List 组件必须显式设置 width 和 height
```

---

## 五、具体修改点（Index.ets）

### 1. 模拟数据修改

```typescript
// 修改前
{ id: 1, name: '跑步', duration: 30, calories: 280, date: '2025-06-20', type: 'run' }

// 修改后
{ id: 1, sport_name: '跑步', duration: 30, calories: 280, sport_date: '2025-06-20', create_time: '2025-06-20 10:00:00' }
```

### 2. 字段引用修改

| 原代码 | 修改后 |
|--------|--------|
| `record.name` | `record.sport_name` |
| `record.date` | `record.sport_date` |
| `record.type` | 删除 |
| `r.date` | `r.sport_date` |

### 3. 日期格式化方法

```typescript
// 修改前
formatDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

// 修改后（保持兼容，sport_date 同样使用 YYYY-MM-DD 格式）
formatDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}
```

---

## 六、EntryAbility 初始化修改

```typescript
import { SportDataManager } from '../data/SportDataManager'

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    // 初始化数据库
    await SportDataManager.getInstance().init(this.context)
  }
}
```

---

## 七、验证检查清单

- [ ] SportRecord 接口字段与数据库表一致
- [ ] Index.ets 中所有 record.name 改为 record.sport_name
- [ ] Index.ets 中所有 record.date 改为 record.sport_date
- [ ] EntryAbility 中初始化 SportDataManager
- [ ] 编译无错误
- [ ] 数据增删改查正常
