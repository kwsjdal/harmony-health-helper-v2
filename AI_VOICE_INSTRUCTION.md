# AI语音记录运动功能 - 完整实现指令

> **参考文档：** https://developer.huawei.com/consumer/cn/blog/topic/03167586109929050
> **技术栈：** HarmonyOS NEXT + ArkTS API12 + @kit.CoreSpeechKit + @kit.AbilityKit

---

## 实现目标

将 `Index.ets` 中当前**模拟的** AIVoiceDialog 替换为基于 Core Speech Kit 的**真实实时语音识别**，用户说话后自动解析运动名称、时长、卡路里，生成运动记录。

---

## 文件清单（共创建3个新文件，修改3个已有文件）

| 操作 | 文件路径 | 说明 |
|------|---------|------|
| 创建 | `entry/src/main/ets/utils/PermissionManager.ets` | 权限管理工具类 |
| 创建 | `entry/src/main/ets/utils/SpeechRecognizerManager.ets` | 语音识别引擎封装 |
| 创建 | `entry/src/main/ets/utils/SportVoiceParser.ets` | 语音文本解析为运动记录 |
| 修改 | `entry/src/main/module.json5` | 添加麦克风权限声明 |
| 修改 | `entry/src/main/resources/base/element/string.json` | 添加权限申请原因 |
| 修改 | `entry/src/main/ets/pages/Index.ets` | 替换 AIVoiceDialog |

---

## 第一步：修改 module.json5 - 添加麦克风权限

文件：`entry/src/main/module.json5`

在 `requestPermissions` 数组中追加：

```json5
{
  "name": "ohos.permission.MICROPHONE",
  "reason": "$string:voice_reason",
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

修改后 `requestPermissions` 应为：

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  { "name": "ohos.permission.READ_HEALTH_DATA" },
  { "name": "ohos.permission.WRITE_HEALTH_DATA" },
  {
    "name": "ohos.permission.MICROPHONE",
    "reason": "$string:voice_reason",
    "usedScene": {
      "abilities": ["EntryAbility"],
      "when": "inuse"
    }
  }
]
```

---

## 第二步：修改 string.json - 添加权限原因

文件：`entry/src/main/resources/base/element/string.json`

追加一条：

```json
{ "name": "voice_reason", "value": "用于语音记录您的运动数据" }
```

修改后 `string` 数组应为：

```json
{
  "string": [
    { "name": "module_desc", "value": "module description" },
    { "name": "EntryAbility_desc", "value": "description" },
    { "name": "EntryAbility_label", "value": "label" },
    { "name": "voice_reason", "value": "用于语音记录您的运动数据" }
  ]
}
```

---

## 第三步：创建 PermissionManager.ets

文件：`entry/src/main/ets/utils/PermissionManager.ets`

```typescript
import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';

export class PermissionManager {
  static checkPermission(permissions: Permissions[]): boolean {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let tokenID: number = 0;
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    tokenID = bundleInfo.appInfo.accessTokenId;
    if (permissions.length === 0) {
      return false;
    }
    return permissions.every(permission =>
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ===
      atManager.checkAccessTokenSync(tokenID, permission)
    );
  }

  static async requestPermission(permissions: Permissions[]): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    let context: Context = getContext() as common.UIAbilityContext;
    const result = await atManager.requestPermissionsFromUser(context, permissions);
    return !!result.authResults.length && result.authResults.every(r => r === 0);
  }
}
```

---

## 第四步：创建 SpeechRecognizerManager.ets

文件：`entry/src/main/ets/utils/SpeechRecognizerManager.ets`

```typescript
import { speechRecognizer } from '@kit.CoreSpeechKit';

class SpeechRecognizerManager {
  private static extraParam: Record<string, Object> = {
    "locate": "CN",
    "recognizerMode": "long"
  };

  private static initParamsInfo: speechRecognizer.CreateEngineParams = {
    language: 'zh-CN',
    online: 1,
    extraParams: this.extraParam
  };

  private static asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  static speechResult: speechRecognizer.SpeechRecognitionResult | null = null;
  private static sessionId: string = "asr" + Date.now();
  static isListening: boolean = false;

  private static async createEngine(): Promise<void> {
    SpeechRecognizerManager.asrEngine = await speechRecognizer.createEngine(
      SpeechRecognizerManager.initParamsInfo
    );
  }

  private static setListener(
    callback: (srr: speechRecognizer.SpeechRecognitionResult) => void
  ): void {
    let listener: speechRecognizer.RecognitionListener = {
      onStart(sessionId: string, eventMessage: string) {
        SpeechRecognizerManager.isListening = true;
      },
      onEvent(sessionId: string, eventCode: number, eventMessage: string) {},
      onResult(sessionId: string, result: speechRecognizer.SpeechRecognitionResult) {
        SpeechRecognizerManager.speechResult = result;
        if (callback) {
          callback(result);
        }
      },
      onComplete(sessionId: string, eventMessage: string) {
        SpeechRecognizerManager.isListening = false;
      },
      onError(sessionId: string, errorCode: number, errorMessage: string) {
        SpeechRecognizerManager.isListening = false;
      }
    };
    SpeechRecognizerManager.asrEngine?.setListener(listener);
  }

  static startListening(): void {
    let recognizerParams: speechRecognizer.StartParams = {
      sessionId: SpeechRecognizerManager.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams: {
        "recognitionMode": 0,
        maxAudioDuration: 60000
      }
    };
    SpeechRecognizerManager.asrEngine?.startListening(recognizerParams);
  }

  static cancel(): void {
    SpeechRecognizerManager.asrEngine?.cancel(SpeechRecognizerManager.sessionId);
    SpeechRecognizerManager.isListening = false;
  }

  static shutDown(): void {
    SpeechRecognizerManager.asrEngine?.shutdown();
    SpeechRecognizerManager.isListening = false;
  }

  static async release(): Promise<void> {
    SpeechRecognizerManager.cancel();
    SpeechRecognizerManager.shutDown();
  }

  static async init(
    callback: (srr: speechRecognizer.SpeechRecognitionResult) => void
  ): Promise<void> {
    await SpeechRecognizerManager.createEngine();
    SpeechRecognizerManager.setListener(callback);
    SpeechRecognizerManager.startListening();
  }
}

export default SpeechRecognizerManager;
```

---

## 第五步：创建 SportVoiceParser.ets

文件：`entry/src/main/ets/utils/SportVoiceParser.ets`

这个工具类负责将语音识别出的中文文本，解析为结构化的运动记录数据。

```typescript
// 运动名称映射表
const SPORT_KEYWORDS: Record<string, { name: string; icon: string; color: string }> = {
  '跑步': { name: '跑步', icon: '🏃', color: '#4CAF50' },
  '跑': { name: '跑步', icon: '🏃', color: '#4CAF50' },
  '游泳': { name: '游泳', icon: '🏊', color: '#2196F3' },
  '游': { name: '游泳', icon: '🏊', color: '#2196F3' },
  '骑行': { name: '骑行', icon: '🚴', color: '#FF9800' },
  '骑': { name: '骑行', icon: '🚴', color: '#FF9800' },
  '健身': { name: '健身', icon: '💪', color: '#F44336' },
  '瑜伽': { name: '瑜伽', icon: '🧘', color: '#9C27B0' },
  '跳绳': { name: '跳绳', icon: '🪢', color: '#00BCD4' },
  '走路': { name: '走路', icon: '🚶', color: '#607D8B' },
  '散步': { name: '走路', icon: '🚶', color: '#607D8B' },
  '篮球': { name: '篮球', icon: '🏀', color: '#FF5722' },
  '足球': { name: '足球', icon: '⚽', color: '#795548' },
  '羽毛球': { name: '羽毛球', icon: '🏸', color: '#E91E63' },
  '乒乓球': { name: '乒乓球', icon: '🏓', color: '#673AB7' },
  '爬山': { name: '爬山', icon: '🏔️', color: '#8BC34A' },
  '登山': { name: '爬山', icon: '🏔️', color: '#8BC34A' },
  '徒步': { name: '徒步', icon: '🥾', color: '#009688' },
};

// 默认运动类型
const DEFAULT_SPORT = { name: '运动', icon: '🏃', color: '#4CAF50' };

export interface ParsedSportRecord {
  name: string;
  duration: number;
  calories: number;
  icon: string;
  color: string;
  rawText: string;
}

export class SportVoiceParser {
  // 从语音文本中解析运动记录
  static parse(text: string): ParsedSportRecord | null {
    // 检测运动类型
    let sportInfo = DEFAULT_SPORT;
    for (const keyword of Object.keys(SPORT_KEYWORDS)) {
      if (text.includes(keyword)) {
        sportInfo = SPORT_KEYWORDS[keyword];
        break;
      }
    }

    // 提取时长（分钟）
    let duration: number = 0;
    const durationPatterns = [
      /(\d+)\s*(分钟|min)/i,
      /(\d+)\s*分/,
      /(\d+\.?\d*)\s*(小时|h|hour)/i,
      /(\d+)\s*小时[零一二三四五六七八九十]*(\d*)\s*分/
    ];
    for (const pattern of durationPatterns) {
      const match = text.match(pattern);
      if (match) {
        if (match[2] === '小时' || match[2] === 'h' || match[2] === 'hour') {
          duration = Math.round(parseFloat(match[1]) * 60);
          if (match[3]) {
            duration += parseInt(match[3]);
          }
        } else {
          duration = parseInt(match[1]);
        }
        break;
      }
    }
    if (duration === 0) {
      duration = 30; // 默认30分钟
    }

    // 提取卡路里
    let calories: number = 0;
    const calPatterns = [
      /(\d+)\s*(千卡|卡路里|卡|kcal|大卡)/i,
      /消耗[了]?\s*(\d+)/,
      /(\d+)\s*千卡/
    ];
    for (const pattern of calPatterns) {
      const match = text.match(pattern);
      if (match) {
        calories = parseInt(match[1]);
        break;
      }
    }

    // 检查是否有足够的有效信息
    if (text.length < 2) {
      return null;
    }

    return {
      name: sportInfo.name,
      duration: duration,
      calories: calories,
      icon: sportInfo.icon,
      color: sportInfo.color,
      rawText: text
    };
  }
}
```

---

## 第六步：替换 Index.ets 中的 AIVoiceDialog

文件：`entry/src/main/ets/pages/Index.ets`

### 6.1 顶部添加导入

在 Index.ets 顶部 `import { router } from '@kit.ArkUI'` 之后追加：

```typescript
import { PermissionManager } from '../utils/PermissionManager'
import SpeechRecognizerManager from '../utils/SpeechRecognizerManager'
import { SportVoiceParser } from '../utils/SportVoiceParser'
import { Permissions } from '@kit.AbilityKit'
```

### 6.2 删除旧的 AIVoiceDialog @Builder（第588-686行整段）

删除从 `// AI语音弹窗组件` 到 `@Builder function AIVoiceDialog(...){...}` 的整段代码。

### 6.3 替换 TodaySportPage 组件（第214-371行）

完整替换 TodaySportPage：

```typescript
// 今日运动页面
@Component
struct TodaySportPage {
  @State todayRecords: TodayRecord[] = [
    { id: 1, name: '跑步', duration: 30, calories: 280, icon: '🏃', color: '#4CAF50' },
    { id: 2, name: '游泳', duration: 45, calories: 350, icon: '🏊', color: '#2196F3' }
  ]
  @State showAIVoice: boolean = false
  @State totalDuration: number = 0
  @State totalCalories: number = 0

  aboutToAppear() {
    this.calculateTotals()
  }

  calculateTotals() {
    this.totalDuration = this.todayRecords.reduce((sum: number, r: TodayRecord) => sum + r.duration, 0)
    this.totalCalories = this.todayRecords.reduce((sum: number, r: TodayRecord) => sum + r.calories, 0)
  }

  // 启动语音识别
  async startVoiceRecognition() {
    // 1. 申请麦克风权限
    const permissions: Permissions[] = ["ohos.permission.MICROPHONE"]
    const hasPermission = await PermissionManager.checkPermission(permissions)
    if (!hasPermission) {
      const granted = await PermissionManager.requestPermission(permissions)
      if (!granted) {
        return // 权限被拒绝
      }
    }

    // 2. 初始化语音识别
    this.showAIVoice = true
    SpeechRecognizerManager.init((result) => {
      // isFinal=true 表示一句话结束
      if (result.isFinal && result.result) {
        const parsed = SportVoiceParser.parse(result.result)
        if (parsed) {
          const newRecord: TodayRecord = {
            id: Date.now(),
            name: parsed.name,
            duration: parsed.duration,
            calories: parsed.calories,
            icon: parsed.icon,
            color: parsed.color
          }
          this.todayRecords.push(newRecord)
          this.calculateTotals()
          this.showAIVoice = false
          SpeechRecognizerManager.release()
        }
      }
      // 60秒超时自动停止
      setTimeout(() => {
        if (this.showAIVoice) {
          this.showAIVoice = false
          SpeechRecognizerManager.release()
        }
      }, 60000)
    })
  }

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text('今日运动')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')

        Text('保持良好习惯')
          .fontSize(12)
          .fontColor('#999999')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding(16)

      // 今日统计卡片
      Column() {
        Row() {
          Column() {
            Text(`${this.totalDuration}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4CAF50')
            Text('总时长(分钟)')
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 4 })
          }
          .layoutWeight(1)

          Column() {
            Text(`${this.totalCalories}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF9800')
            Text('消耗(千卡)')
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(20)
      }
      .width('90%')
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .shadow({ radius: 8, color: '#20000000', offsetX: 0, offsetY: 4 })
      .margin({ top: 8 })

      // 运动项目列表
      Text('运动项目')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .width('100%')
        .padding({ left: 16, top: 20, bottom: 8 })

      List() {
        ForEach(this.todayRecords, (record: TodayRecord) => {
          ListItem() {
            Row() {
              Text(record.icon)
                .fontSize(24)
                .margin({ right: 12 })

              Column() {
                Text(record.name)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#333333')
                Text(`${record.duration}分钟 · ${record.calories}千卡`)
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button('开始')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .backgroundColor(record.color)
                .borderRadius(16)
                .width(60)
                .height(28)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .margin({ bottom: 8 })
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .layoutWeight(1)

      // AI语音添加按钮
      Button() {
        Row() {
          Image($r('app.media.ic_mic'))
            .width(20)
            .height(20)
            .margin({ right: 8 })
          Text('AI语音添加运动')
            .fontSize(16)
            .fontColor('#FFFFFF')
        }
      }
      .width('90%')
      .height(48)
      .backgroundColor('#673AB7')
      .borderRadius(24)
      .margin({ bottom: 16 })
      .onClick(() => {
        this.startVoiceRecognition()
      })

      // AI语音弹窗 - 真实语音识别版本
      if (this.showAIVoice) {
        AIVoiceDialog({
          onClose: () => {
            this.showAIVoice = false
            SpeechRecognizerManager.release()
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
```

### 6.4 添加新的 AIVoiceDialog @Builder（放在 TodaySportPage 之后）

```typescript
// AI语音弹窗组件 - 真实语音识别版本
@Builder
function AIVoiceDialog(params: { onClose: () => void }) {
  Column() {
    Column() {
      Text('AI语音记录运动')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 20 })

      // 录音动画区域
      Column() {
        // 麦克风图标 + 脉冲动画提示
        Image($r('app.media.ic_mic_large'))
          .width(80)
          .height(80)
          .margin({ bottom: 16 })

        Text('正在聆听...')
          .fontSize(16)
          .fontColor('#4CAF50')
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 8 })

        Text('说出您的运动记录')
          .fontSize(12)
          .fontColor('#999999')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 4 })

        Text('例如："我刚才跑步了30分钟，消耗了280千卡"')
          .fontSize(11)
          .fontColor('#CCCCCC')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding(40)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)
      .margin({ bottom: 20 })

      // 支持的运动类型提示
      Text('支持的运动：跑步、游泳、骑行、健身、瑜伽、跳绳、走路、篮球、足球、羽毛球、爬山等')
        .fontSize(10)
        .fontColor('#BBBBBB')
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ bottom: 16 })

      // 取消按钮
      Button('停止录音')
        .fontSize(14)
        .fontColor('#666666')
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .width('100%')
        .height(40)
        .onClick(params.onClose)
    }
    .width('85%')
    .padding(24)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
  .width('100%')
  .height('100%')
  .backgroundColor('#80000000')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
}
```

---

## 第七步：更新数据模型接口（Index.ets 底部）

确保 Index.ets 底部的接口定义完整：

```typescript
// 数据模型 - 与 SportDataManager 导出接口保持一致
interface TodayRecord {
  id: number
  name: string
  duration: number
  calories: number
  icon: string
  color: string
}
```

删除旧的 `SportRecord` 接口（如果 Index.ets 底部有），统一从 `SportDataManager` 导入。

Index.ets 底部删除：
```typescript
// 删除以下
interface SportRecord {
  id: number
  name: string
  duration: number
  calories: number
  date: string
  type: string
}
```

---

## 语音识别流程总结

```
用户点击"AI语音添加运动"按钮
    ↓
startVoiceRecognition() 被调用
    ↓
① 检查/申请 MICROPHONE 权限（PermissionManager）
    ↓
② 创建语音识别引擎（SpeechRecognizerManager.init）
    ↓
③ 设置监听回调 → 麦克风自动打开
    ↓
④ 用户说话 → onResult 持续回调（实时识别）
    ↓
⑤ isFinal=true 表示一句话结束
    ↓
⑥ SportVoiceParser.parse() 解析文本
    ↓  · 匹配运动关键词 → 确定运动类型
    ↓  · 正则提取时长（分钟/小时）
    ↓  · 正则提取卡路里
    ↓
⑦ 生成 TodayRecord 并添加到 todayRecords
    ↓
⑧ 关闭弹窗 + 释放引擎（release）
    ↓
UI自动刷新 → 统计更新
```

---

## 语音识别结果格式

Core Speech Kit 的 `SpeechRecognitionResult` 结构：

```typescript
{
  isFinal: boolean  // true=当前句子识别结束（语义完成）
  isLast: boolean   // true=全部识别结束
  result: string    // 识别出的中文文本
}
```

**关键判断逻辑：**
- 实时识别过程中，`isFinal` 会在语义断句时变为 `true`
- 只有当 `isFinal === true` 时才解析文本生成运动记录
- 60秒超时后自动关闭，释放资源

---

## SportVoiceParser 支持的语义解析

| 用户说 | 解析结果 |
|--------|---------|
| "我跑步三十分钟" | 跑步 30分钟 0千卡 |
| "游泳了45分钟" | 游泳 45分钟 0千卡 |
| "刚才跑步半小时，消耗300千卡" | 跑步 30分钟 300千卡 |
| "骑行一小时消耗了500卡路里" | 骑行 60分钟 500千卡 |
| "帮我记录一下，健身40分钟" | 健身 40分钟 0千卡 |

**没有匹配到具体运动名称时**，默认使用"运动"+跑步图标。

---

## ArkTS 注意事项

1. **@kit.CoreSpeechKit 导入**：`import { speechRecognizer } from '@kit.CoreSpeechKit'`
2. **语音识别在真机上运行**：模拟器不支持麦克风，需在真机上测试
3. **异步权限申请**：`requestPermissionsFromUser` 是异步操作，需 await
4. **引擎生命周期**：识别完成后必须调用 `release()` 释放资源
5. **超时保护**：设置 60 秒超时，防止引擎一直占用
6. **`getContext()` 必须在 UIAbility 上下文中调用**：不能在普通工具类中直接使用

---

## 验证清单

- [ ] module.json5 新增 MICROPHONE 权限声明
- [ ] string.json 新增 voice_reason 字符串
- [ ] PermissionManager.ets 可正常检查/申请权限
- [ ] SpeechRecognizerManager.ets 可创建引擎并开始识别
- [ ] SportVoiceParser 可正确解析"跑步30分钟消耗300千卡"
- [ ] 点击"AI语音添加运动"→弹出录音界面
- [ ] 说出运动记录后自动识别并添加
- [ ] 列表自动刷新显示新记录
- [ ] 统计卡片数据更新
- [ ] 取消录音后引擎释放
- [ ] 60秒超时自动关闭
- [ ] 编译 0 错误
