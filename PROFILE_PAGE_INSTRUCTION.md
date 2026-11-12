# "我的"页面完整实现指令

## 目标

将 `entry/src/main/ets/pages/Index.ets` 中的 `ProfilePage` 组件替换为功能完整的"我的"页面。

---

## 最终效果

```
┌──────────────────────────────────────┐
│  ← 返回          我的                │  导航栏
├──────────────────────────────────────┤
│                                      │
│           [头像 80x80 圆形]           │  用户头像
│           运动达人                     │  昵称（可编辑）
│       ID: HS20250001                  │  用户ID
│                                      │
│  ┌────────┬────────┬────────┬──────┐  │
│  │  坚持  │  累计  │  累计  │ 运动 │  │  统计卡片行
│  │  运动  │  运动  │  消耗  │ 排名 │  │
│  │  128天 │  128次 │15680卡│ 85%  │  │
│  └────────┴────────┴────────┴──────┘  │
│                                      │
│  ┌──────────────────────────────────┐ │
│  │ 🏆  本周成就                      │ │  成就卡片
│  │  完成5次运动 · 消耗2000千卡      │ │
│  │  [===========     ] 3/5          │ │
│  └──────────────────────────────────┘ │
│                                      │
│  ┌──────────────────────────────────┐ │
│  │ 运动目标         10000步/天  >   │ │  设置菜单
│  │ 体重管理         70kg       >   │ │
│  │ 运动排行         查看好友排名 >  │ │
│  │ 运动提醒         已开启      >   │ │
│  │ 数据管理         导出/同步   >   │ │
│  │ 关于我们         v1.0.0     >   │ │
│  └──────────────────────────────────┘ │
│                                      │
│          [ 退出登录 ]                 │  退出按钮
│                                      │
├──────────────────────────────────────┤
│  ●运动记录   ●今日运动   ●我的       │  底部Tab
└──────────────────────────────────────┘
```

---

## 修改文件

**只修改一个文件：** `entry/src/main/ets/pages/Index.ets`

**修改范围：** 替换现有的 `ProfilePage` 组件（第374-466行），并新增弹窗子组件。

---

## 第一步：删除旧的 ProfilePage（Index.ets 第374-466行）

删除从 `// 我的页面` 到 `@Component struct ProfilePage {...}` 整段代码，以及旧的 `ProfileItem` @Builder（第690-710行）。

---

## 第二步：新增 ProfilePage 组件（替换位置）

```typescript
// ==================== 我的页面 ====================

// 成就数据模型
interface Achievement {
  title: string
  desc: string
  current: number
  target: number
  icon: string
}

@Component
struct ProfilePage {
  // 用户数据
  @State userName: string = '运动达人'
  @State userId: string = 'HS20250001'
  @State userMotto: string = '坚持运动，健康生活'

  // 统计数据
  @State continueDays: number = 128
  @State totalWorkouts: number = 128
  @State totalCalories: number = 15680
  @State rankPercent: number = 85

  // 设置数据
  @State dailyGoal: number = 10000
  @State userWeight: number = 70
  @State reminderEnabled: boolean = true
  @State strideLength: number = 0.7

  // 弹窗控制
  @State showGoalDialog: boolean = false
  @State showWeightDialog: boolean = false
  @State showReminderDialog: boolean = false
  @State showAboutDialog: boolean = false
  @State showEditNameDialog: boolean = false

  // 成就数据
  @State weekAchievement: Achievement = {
    title: '本周成就',
    desc: '完成本周运动目标',
    current: 3,
    target: 5,
    icon: '🏆'
  }

  aboutToAppear() {
    this.loadUserData()
  }

  async loadUserData() {
    try {
      const dataManager = SportDataManager.getInstance()
      const stats = await dataManager.getStatistics()
      this.totalWorkouts = stats.totalWorkouts
      this.totalCalories = stats.totalCalories

      const settings = await dataManager.getSettings()
      this.dailyGoal = settings.goal
      this.userWeight = settings.weight
      this.strideLength = settings.strideLength
      this.reminderEnabled = settings.reminderEnabled
    } catch (e) {
      // 使用默认值
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // ===== 1. 用户信息卡片 =====
          this.BuildUserCard()

          // ===== 2. 统计卡片行 =====
          this.BuildStatsRow()

          // ===== 3. 本周成就卡片 =====
          this.BuildAchievementCard()

          // ===== 4. 设置菜单 =====
          Column() {
            this.BuildMenuItem('运动目标', `${this.dailyGoal}步/天`, '🎯', () => {
              this.showGoalDialog = true
            })
            this.BuildMenuItem('体重管理', `${this.userWeight}kg`, '⚖️', () => {
              this.showWeightDialog = true
            })
            this.BuildMenuItem('运动排行', '查看好友排名', '📊', () => {
              // 跳转到排行页面
            })
            this.BuildMenuItem('运动提醒', this.reminderEnabled ? '已开启' : '已关闭', '🔔', () => {
              this.showReminderDialog = true
            })
            this.BuildMenuItem('数据管理', '导出/同步', '💾', () => {
              // 跳转到数据管理页面
            })
            this.BuildMenuItem('关于我们', 'v1.0.0', 'ℹ️', () => {
              this.showAboutDialog = true
            })
          }
          .width('100%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ top: 12, left: 16, right: 16 })

          // ===== 5. 退出登录按钮 =====
          Button('退出登录')
            .fontSize(16)
            .fontColor('#FF5252')
            .backgroundColor('#FFFFFF')
            .width('100%')
            .height(48)
            .borderRadius(12)
            .margin({ top: 16, left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F5F5')
      .scrollBar(BarState.Off)

      // ===== 弹窗层 =====
      if (this.showEditNameDialog) {
        this.BuildEditNameDialog()
      }
      if (this.showGoalDialog) {
        this.BuildGoalDialog()
      }
      if (this.showWeightDialog) {
        this.BuildWeightDialog()
      }
      if (this.showReminderDialog) {
        this.BuildReminderDialog()
      }
      if (this.showAboutDialog) {
        this.BuildAboutDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 子组件构建器 ====================

  @Builder
  BuildUserCard() {
    Column() {
      Row({ space: 12 }) {
        // 头像
        Column() {
          Image($r('app.media.ic_avatar'))
            .width(64)
            .height(64)
            .borderRadius(32)
            .border({ width: 2, color: '#FFFFFF' })
        }
        .width(68)
        .height(68)
        .borderRadius(34)
        .backgroundColor('#4CAF50')
        .justifyContent(FlexAlign.Center)

        // 用户信息
        Column() {
          Row({ space: 8 }) {
            Text(this.userName)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')

            Image($r('app.media.ic_edit'))
              .width(16)
              .height(16)
              .onClick(() => {
                this.showEditNameDialog = true
              })
          }

          Text(`ID: ${this.userId}`)
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.7)')
            .margin({ top: 4 })

          Text(this.userMotto)
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.85)')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 20, bottom: 20, left: 20, right: 20 })
    }
    .width('100%')
    .borderRadius({ bottomLeft: 24, bottomRight: 24 })
    .linearGradient({
      direction: GradientDirection.Right,
      colors: [['#4CAF50', 0], ['#2E7D32', 1]]
    })
  }

  @Builder
  BuildStatsRow() {
    Row() {
      this.BuildStatItem('坚持运动', `${this.continueDays}天`, '#4CAF50')
      this.BuildStatItem('累计运动', `${this.totalWorkouts}次`, '#FF9800')
      this.BuildStatItem('累计消耗', `${this.totalCalories}千卡`, '#2196F3')
      this.BuildStatItem('运动排名', `前${this.rankPercent}%`, '#9C27B0')
    }
    .width('100%')
    .padding(16)
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  BuildStatItem(label: string, value: string, color: string) {
    Column({ space: 6 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(11)
        .fontColor('#999999')
    }
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  BuildAchievementCard() {
    Column() {
      Row({ space: 12 }) {
        Text(this.weekAchievement.icon)
          .fontSize(32)

        Column() {
          Text(this.weekAchievement.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
          Text(this.weekAchievement.desc)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(`${this.weekAchievement.current}/${this.weekAchievement.target}`)
          .fontSize(14)
          .fontColor('#4CAF50')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      // 进度条
      Stack() {
        Rect()
          .width('100%')
          .height(6)
          .fill('#E8F5E9')
          .borderRadius(3)
        Rect()
          .width(`${(this.weekAchievement.current / this.weekAchievement.target) * 100}%`)
          .height(6)
          .fill('#4CAF50')
          .borderRadius(3)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .margin({ top: 12, left: 16, right: 16 })
  }

  @Builder
  BuildMenuItem(title: string, value: string, icon: string, onClick: () => void) {
    Row() {
      Text(icon)
        .fontSize(20)
        .margin({ right: 12 })

      Text(title)
        .fontSize(15)
        .fontColor('#333333')
        .layoutWeight(1)

      Text(value)
        .fontSize(13)
        .fontColor('#999999')
        .margin({ right: 4 })

      Image($r('app.media.ic_arrow_right'))
        .width(14)
        .height(14)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .border({ width: { bottom: 1 }, color: '#F5F5F5' })
    .onClick(onClick)
  }

  // ==================== 弹窗组件 ====================

  // 修改昵称弹窗
  @Builder
  BuildEditNameDialog() {
    Column() {
      Column() {
        Text('修改昵称')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 20 })

        TextInput({ text: this.userName })
          .width('100%')
          .height(44)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding(12)
          .onChange((value: string) => {
            this.userName = value
          })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.showEditNameDialog = false
            })

          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.showEditNameDialog = false
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#60000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.showEditNameDialog = false
    })
  }

  // 运动目标弹窗
  @Builder
  BuildGoalDialog() {
    Column() {
      Column() {
        Text('设置运动目标')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 20 })

        Text(`${this.dailyGoal} 步/天`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#4CAF50')
          .margin({ bottom: 16 })

        // 预设目标选择
        Row({ space: 8 }) {
          ForEach([5000, 8000, 10000, 15000, 20000], (goal: number) => {
            Button(`${goal}`)
              .fontSize(13)
              .fontColor(this.dailyGoal === goal ? '#FFFFFF' : '#666666')
              .backgroundColor(this.dailyGoal === goal ? '#4CAF50' : '#F5F5F5')
              .borderRadius(16)
              .height(32)
              .onClick(() => {
                this.dailyGoal = goal
              })
          })
        }
        .width('100%')
        .margin({ bottom: 16 })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => { this.showGoalDialog = false })

          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              const dataManager = SportDataManager.getInstance()
              dataManager.saveSettings({
                goal: this.dailyGoal,
                weight: this.userWeight,
                strideLength: this.strideLength,
                reminderEnabled: this.reminderEnabled
              })
              this.showGoalDialog = false
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#60000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.showGoalDialog = false })
  }

  // 体重管理弹窗
  @Builder
  BuildWeightDialog() {
    Column() {
      Column() {
        Text('体重管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 20 })

        Row() {
          Button('-')
            .fontSize(24)
            .fontColor('#4CAF50')
            .backgroundColor('#F5F5F5')
            .width(44)
            .height(44)
            .borderRadius(22)
            .onClick(() => {
              if (this.userWeight > 30) {
                this.userWeight -= 1
              }
            })

          Text(`${this.userWeight}`)
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ left: 24, right: 24 })

          Button('+')
            .fontSize(24)
            .fontColor('#4CAF50')
            .backgroundColor('#F5F5F5')
            .width(44)
            .height(44)
            .borderRadius(22)
            .onClick(() => {
              if (this.userWeight < 200) {
                this.userWeight += 1
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 4 })

        Text('kg')
          .fontSize(14)
          .fontColor('#999999')

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => { this.showWeightDialog = false })

          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              const dataManager = SportDataManager.getInstance()
              dataManager.saveSettings({
                goal: this.dailyGoal,
                weight: this.userWeight,
                strideLength: this.strideLength,
                reminderEnabled: this.reminderEnabled
              })
              this.showWeightDialog = false
            })
        }
        .width('100%')
        .margin({ top: 24 })
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#60000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.showWeightDialog = false })
  }

  // 运动提醒弹窗
  @Builder
  BuildReminderDialog() {
    Column() {
      Column() {
        Text('运动提醒')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ bottom: 20 })

        Row() {
          Text('开启运动提醒')
            .fontSize(16)
            .fontColor('#333333')
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
            .onChange((isOn: boolean) => {
              this.reminderEnabled = isOn
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .margin({ bottom: 8 })

        if (this.reminderEnabled) {
          Row() {
            Text('提醒时间')
              .fontSize(16)
              .fontColor('#333333')
              .layoutWeight(1)

            Text('08:00')
              .fontSize(16)
              .fontColor('#4CAF50')
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
        }

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => { this.showReminderDialog = false })

          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => { this.showReminderDialog = false })
        }
        .width('100%')
        .margin({ top: 24 })
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#60000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.showReminderDialog = false })
  }

  // 关于弹窗
  @Builder
  BuildAboutDialog() {
    Column() {
      Column() {
        Column({ space: 12 }) {
          Image($r('app.media.ic_avatar'))
            .width(60)
            .height(60)
            .borderRadius(30)

          Text('健康运动助手')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')

          Text('version 1.0.0')
            .fontSize(13)
            .fontColor('#999999')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 16 })

        Column() {
          Text('健康运动助手是一款专为运动爱好者设计的数据记录与分析工具，帮助您追踪每一次运动，养成健康生活习惯。')
            .fontSize(13)
            .fontColor('#666666')
            .lineHeight(20)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)

        Row() {
          Button('我知道了')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .borderRadius(8)
            .width('100%')
            .height(40)
            .onClick(() => { this.showAboutDialog = false })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#60000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.showAboutDialog = false })
  }
}
```

---

## 第三步：确保导入正确

Index.ets 顶部需要引入 SportDataManager：

```typescript
import { router } from '@kit.ArkUI'
import { SportDataManager } from '../data/SportDataManager'
```

---

## 第四步：删除旧的 ProfileItem @Builder（第690-710行）

```typescript
// 删除以下整段
@Builder
function ProfileItem(title: string, value: string) {
  Row() { ... }
  // 不再需要，已在 ProfilePage 内用 BuildMenuItem 替代
}
```

---

## 功能清单对照

| 功能项 | 实现方式 | 交互 |
|--------|---------|------|
| 用户头像 | `Image($r('app.media.ic_avatar'))` 圆形展示 | 不可点击 |
| 用户昵称 | `@State userName` 显示 | 点击编辑图标弹出修改弹窗 |
| 用户ID | 固定显示 `HS20250001` | 只读 |
| 个性签名 | `@State userMotto` | 只读 |
| 坚持运动天数 | `@State continueDays` | 只读 |
| 累计运动次数 | `SportDataManager.getStatistics()` | 自动加载 |
| 累计消耗 | `SportDataManager.getStatistics()` | 自动加载 |
| 运动排名 | `@State rankPercent` | 只读 |
| 本周成就 | `@State weekAchievement` + 进度条 | 只读 |
| 运动目标 | 弹窗 + 预设目标按钮 | 点击打开修改弹窗 |
| 体重管理 | 弹窗 + 加减按钮 | 点击打开调整弹窗 |
| 运动排行 | 菜单项 | 预留 navigator 跳转 |
| 运动提醒 | 弹窗 + Toggle 开关 | 点击打开设置弹窗 |
| 数据管理 | 菜单项 | 预留 navigator 跳转 |
| 关于我们 | 弹窗 + 版本号 | 点击打开关于弹窗 |
| 退出登录 | 红色按钮 | 点击退出 |

---

## ArkTS 注意事项

1. **所有 `ForEach` 回调显式类型**：`ForEach([5000,8000,10000], (goal: number) => {...})`
2. **Switch 组件 API**：使用 `Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })`
3. **Async/await 在 aboutToAppear**：`aboutToAppear` 方法中异步调用需要 try/catch
4. **弹窗遮罩**：每个弹窗外层 Column 使用 `.backgroundColor('#60000000')` 作半透明遮罩，点击遮罩关闭
5. **线性渐变**：`linearGradient({ direction: GradientDirection.Right, colors: [['#4CAF50', 0], ['#2E7D32', 1]] })`

---

## 验证清单

- [ ] 用户信息卡片渐变背景正常显示
- [ ] 四列统计数据行布局正确
- [ ] 本周成就进度条正常
- [ ] 六项设置菜单可点击
- [ ] 修改昵称弹窗可打开、输入、保存
- [ ] 运动目标弹窗可切换预设值
- [ ] 体重管理弹窗加减按钮正常
- [ ] 运动提醒开关 Toggle 正常
- [ ] 关于弹窗显示版本号
- [ ] 退出登录按钮显示
- [ ] 页面可滚动
- [ ] 编译无错误
