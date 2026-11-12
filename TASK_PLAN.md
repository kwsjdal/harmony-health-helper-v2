# 健康运动助手 - 自动修复Bug任务计划

> **目标：** 基于鸿蒙HarmonyOS NEXT + ArkTS API12，实现一个健康运动助手APP，支持运动记录、AI语音添加、数据统计等功能。
> **技术栈：** ArkTS, ArkUI, @kit.ArkData, @kit.AbilityKit, @kit.ArkUI

---

## 项目结构

```
HealthSportAssistant/
├── build-profile.json5          # 应用级构建配置
├── hvigorfile.ts               # Hvigor构建脚本
├── oh-package.json5            # 应用级依赖
└── entry/
    ├── build-profile.json5      # 模块级构建配置
    ├── hvigorfile.ts           # 模块级Hvigor脚本
    ├── oh-package.json5        # 模块级依赖
    └── src/main/
        ├── ets/
        │   ├── entryability/
        │   │   └── EntryAbility.ets    # 入口Ability
        │   ├── pages/
        │   │   └── Index.ets           # 主页面（Tab布局）
        │   └── data/
        │       └── SportDataManager.ets # 数据管理器
        ├── resources/
        │   └── base/
        │       ├── element/string.json  # 字符串资源
        │       ├── media/               # 图片资源（需自行添加）
        │       ├── profile/main_pages.json # 页面路由
        │       └── theme.json           # 主题配置
        └── module.json5               # 模块配置
```

---

## Task 1: 项目初始化与基础配置

**目标：** 创建完整的鸿蒙项目结构，确保编译通过。

**文件清单：**
- 创建：`build-profile.json5`, `hvigorfile.ts`, `oh-package.json5`
- 创建：`entry/build-profile.json5`, `entry/hvigorfile.ts`, `entry/oh-package.json5`
- 创建：`entry/src/main/module.json5`, `entry/src/main/resources/base/profile/main_pages.json`
- 创建：`entry/src/main/resources/base/element/string.json`, `entry/src/main/resources/base/theme.json`

**Bug修复清单：**
1. **签名配置缺失** - 若编译报错"signingConfig not found"，在 `build-profile.json5` 的 `app.signingConfigs` 中添加调试签名或留空数组
2. **SDK版本不匹配** - 确保 `compileSdkVersion` 和 `compatibleSdkVersion` 统一为 12
3. **模块路径错误** - 确认 `modules[].srcPath` 为 `"./entry"`

**验证命令：**
```bash
# 在项目根目录执行
hvigor build
```

---

## Task 2: 入口Ability实现

**目标：** 实现应用入口Ability，正确加载主页面。

**文件：**
- 创建：`entry/src/main/ets/entryability/EntryAbility.ets`

**Bug修复清单：**
1. **导入路径错误** - 使用 `@kit.AbilityKit` 而非旧版 `@ohos.app.ability.UIAbility`
2. **WindowStage加载失败** - 检查 `loadContent` 的页面路径是否为 `"pages/Index"`，与 `main_pages.json` 保持一致
3. **生命周期日志不输出** - 确认 `hilog` 导入自 `@kit.PerformanceAnalysisKit`

**关键代码：**
```typescript
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded');
    });
  }
}
```

---

## Task 3: 数据管理器实现

**目标：** 实现运动数据的持久化存储与管理。

**文件：**
- 创建：`entry/src/main/ets/data/SportDataManager.ets`

**Bug修复清单：**
1. **preferences导入错误** - 使用 `@kit.ArkData` 而非 `@ohos.data.preferences`
2. **Context类型未定义** - 方法参数使用 `Context` 类型，确保在Ability中传入 `this.context`
3. **异步操作未await** - `put` 和 `flush` 必须 await，否则数据丢失
4. **JSON解析异常** - `getSync` 返回空字符串时，提供默认值 `'[]'`
5. **单例初始化时机** - 在 `EntryAbility.onCreate` 中调用 `SportDataManager.getInstance().init(this.context)`

**关键代码：**
```typescript
import { preferences } from '@kit.ArkData';

export class SportDataManager {
  private static instance: SportDataManager
  private pref: preferences.Preferences | null = null

  async init(context: Context): Promise<void> {
    this.pref = preferences.getPreferencesSync(context, { name: 'sport_data' })
  }

  async getRecords(): Promise<SportRecord[]> {
    if (!this.pref) return []
    const data = this.pref.getSync('records', '[]') as string
    return JSON.parse(data)
  }
}
```

---

## Task 4: 主页面Tab布局实现

**目标：** 实现底部Tab导航，包含"运动记录"、"今日运动"、"我的"三个页面。

**文件：**
- 创建：`entry/src/main/ets/pages/Index.ets`

**Bug修复清单：**
1. **TabsController未初始化** - 必须 `new TabsController()`，否则切换失效
2. **TabBar点击不切换** - 确保 `onClick` 中同时修改 `currentIndex` 和调用 `tabsController.changeIndex()`
3. **图片资源缺失** - 若 `$r('app.media.ic_record')` 报错，需在 `resources/base/media` 放置对应图片，或先用Text替代
4. **组件未导出** - 子组件（SportRecordPage, TodaySportPage, ProfilePage）需在同一个文件中定义或正确导入

**关键代码：**
```typescript
@Entry
@Component
struct Index {
  @State currentIndex: number = 0
  private tabsController: TabsController = new TabsController()

  @Builder
  TabBuilder(title: string, targetIndex: number, selectedImg: Resource, normalImg: Resource) {
    Column() {
      Image(this.currentIndex === targetIndex ? selectedImg : normalImg)
      Text(title)
        .fontColor(this.currentIndex === targetIndex ? '#4CAF50' : '#999999')
    }
    .onClick(() => {
      this.currentIndex = targetIndex
      this.tabsController.changeIndex(targetIndex)
    })
  }
}
```

---

## Task 5: 运动记录页面实现

**目标：** 实现周历视图和运动记录列表，支持添加记录。

**Bug修复清单：**
1. **日期格式化错误** - 月份和日期需补零：`String(date.getMonth() + 1).padStart(2, '0')`
2. **周历计算错误** - 周日 `getDay()` 返回0，需特殊处理：`diff = date - day + (day === 0 ? -6 : 1)`
3. **ForEach类型推断失败** - 显式声明lambda参数类型：`(day: Date, index: number) => {...}`
4. **弹窗条件渲染问题** - 使用 `if (this.showAddDialog)` 条件渲染，确保状态变更触发UI更新
5. **记录列表不刷新** - 添加记录后需确保 `recordList` 是 `@State` 装饰的响应式变量

**关键代码：**
```typescript
getWeekDays(): Date[] {
  const days: Date[] = []
  const startOfWeek = new Date(this.currentWeek)
  const day = startOfWeek.getDay()
  const diff = startOfWeek.getDate() - day + (day === 0 ? -6 : 1)
  startOfWeek.setDate(diff)
  for (let i = 0; i < 7; i++) {
    const d = new Date(startOfWeek)
    d.setDate(startOfWeek.getDate() + i)
    days.push(d)
  }
  return days
}
```

---

## Task 6: 今日运动页面实现

**目标：** 实现今日运动统计和运动项目列表，支持AI语音添加。

**Bug修复清单：**
1. **统计数据不更新** - `totalDuration` 和 `totalCalories` 需用 `@State` 装饰，并在 `aboutToAppear` 中初始化
2. **reduce类型错误** - 显式指定初始值：`records.reduce((sum, r) => sum + r.duration, 0)`
3. **按钮样式不生效** - `Button` 内嵌 `Row` 时，需使用 `Button() { Row() {...} }` 语法
4. **AI语音弹窗不关闭** - 确保 `onClose` 回调正确修改 `showAIVoice` 状态

**关键代码：**
```typescript
@Component
struct TodaySportPage {
  @State todayRecords: TodayRecord[] = []
  @State totalDuration: number = 0
  @State totalCalories: number = 0

  aboutToAppear() {
    this.calculateTotals()
  }

  calculateTotals() {
    this.totalDuration = this.todayRecords.reduce((sum, r) => sum + r.duration, 0)
    this.totalCalories = this.todayRecords.reduce((sum, r) => sum + r.calories, 0)
  }
}
```

---

## Task 7: 我的页面实现

**目标：** 实现用户信息展示和设置列表。

**Bug修复清单：**
1. **布局对齐问题** - 使用 `alignItems(HorizontalAlign.Center)` 确保内容居中
2. **分割线不显示** - `border` 属性需指定 `width: { bottom: 1 }` 和 `color`
3. **图片资源缺失** - 头像图片需放置于 `resources/base/media`，或使用占位符

---

## Task 8: 弹窗组件实现

**目标：** 实现添加记录弹窗和AI语音弹窗。

**Bug修复清单：**
1. **@Builder参数传递** - 使用对象包裹回调函数：`{ onClose: () => void, onConfirm: (record) => void }`
2. **遮罩层不覆盖全屏** - 外层 `Column` 设置 `.width('100%').height('100%').backgroundColor('#80000000')`
3. **输入框类型错误** - 数字输入使用 `.type(InputType.Number)`
4. **DatePicker高度异常** - 显式设置 `.height(120)` 避免布局溢出

**关键代码：**
```typescript
@Builder
function AddRecordDialog(params: { onClose: () => void, onConfirm: (record: SportRecord) => void }) {
  Column() {
    Column() {
      // 弹窗内容
    }
    .width('85%')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
  .width('100%')
  .height('100%')
  .backgroundColor('#80000000')
  .justifyContent(FlexAlign.Center)
}
```

---

## Task 9: 资源文件配置

**目标：** 配置字符串、颜色、图片等资源。

**Bug修复清单：**
1. **string.json格式错误** - 确保为数组格式：`{ "string": [{ "name": "...", "value": "..." }] }`
2. **main_pages路径错误** - 页面路径与文件实际路径一致：`"pages/Index"`
3. **theme.json字体配置** - 中文字体使用 `NotoSansCJKsc`，确保文件存在
4. **module.json5权限声明** - 健康数据读写需声明：`ohos.permission.READ_HEALTH_DATA`, `ohos.permission.WRITE_HEALTH_DATA`

---

## Task 10: 编译验证与最终修复

**验证清单：**
- [ ] 项目无编译错误
- [ ] Tab切换正常
- [ ] 周历显示正确
- [ ] 记录添加/删除正常
- [ ] 统计数据计算正确
- [ ] 弹窗打开/关闭正常
- [ ] 数据持久化正常

**常见编译错误修复：**

| 错误信息 | 原因 | 修复方案 |
|---------|------|---------|
| `Cannot find module '@ohos/...'` | 使用旧版API | 替换为 `@kit.xxx` 新路径 |
| `Property 'xxx' does not exist` | 类型不匹配 | 检查接口定义，确保字段存在 |
| `Expected 1 arguments, but got 0` | 参数缺失 | 补充必要参数，如上下文Context |
| `This expression is not callable` | 函数调用错误 | 检查是否为方法而非属性 |
| `Resource not found` | 资源缺失 | 在resources中添加对应资源文件 |

---

## 自动化修复脚本（可选）

在项目根目录创建 `fix-common-issues.py`：

```python
import os
import re

def fix_imports(file_path):
    """修复旧版导入路径"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 替换旧版导入
    replacements = {
        "@ohos.app.ability.UIAbility": "@kit.AbilityKit",
        "@ohos.data.preferences": "@kit.ArkData",
        "@ohos.router": "@kit.ArkUI",
        "@ohos.window": "@kit.ArkUI",
    }

    for old, new in replacements.items():
        content = content.replace(old, new)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

def scan_project(project_path):
    """扫描项目中的所有.ets文件"""
    for root, dirs, files in os.walk(project_path):
        for file in files:
            if file.endswith('.ets'):
                fix_imports(os.path.join(root, file))

if __name__ == '__main__':
    scan_project('.')
    print("导入路径修复完成")
```

---

## 执行顺序

1. 按 Task 1-9 顺序创建文件
2. 每完成一个Task，执行 `hvigor build` 验证
3. 遇到编译错误，参考对应Task的"Bug修复清单"
4. 全部完成后，执行 Task 10 的最终验证

---

## 备注

- 图片资源（`ic_record.png`, `ic_today.png`, `ic_profile.png` 等）需自行准备或先用Text替代
- 真机调试需申请 `ohos.permission.READ_HEALTH_DATA` 权限
- AI语音功能当前为模拟实现，实际接入需集成语音识别SDK
