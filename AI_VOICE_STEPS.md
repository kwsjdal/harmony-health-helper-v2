# AI 语音记录运动 — 完整操作步骤

## 改前备份

复制整个项目文件夹，在副本上操作。原项目不动。

---

## 步骤 1：新建文件 `entry/src/main/ets/utils/PermissionManager.ets`

在 `entry/src/main/ets/utils/` 下新建文件，粘贴以下内容：

```typescript
import { abilityAccessCtrl, bundleManager } from '@kit.AbilityKit';

export class PermissionManager {
  static checkPermission(permission: string): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo: Record<string, Object> =
        bundleManager.getBundleInfoForSelfSync(
          bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
        ) as Record<string, Object>;
      const appInfo = bundleInfo['appInfo'] as Record<string, Object>;
      const tokenID = appInfo['accessTokenId'] as number;
      const status = atManager.checkAccessTokenSync(tokenID, permission);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_e) {
      return false;
    }
  }

  static async requestPermission(permission: string): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const context = getContext();
      const result: Record<string, Object> =
        await atManager.requestPermissionsFromUser(context, [permission]) as Record<string, Object>;
      const authResults = result['authResults'] as number[];
      return authResults.length > 0 && authResults.every((r: number) => r === 0);
    } catch (_e) {
      return false;
    }
  }
}
```

---

## 步骤 2：新建文件 `entry/src/main/ets/utils/SpeechRecognizerManager.ets`

```typescript
import { speechRecognizer } from '@kit.CoreSpeechKit';

class SpeechRecognizerManager {
  private static asrEngine: Object | null = null;
  private static sessionId: string = 'asr_' + Date.now();
  private static resultCallback: ((text: string, isFinal: boolean) => void) | null = null;
  static isListening: boolean = false;

  static async init(callback: (text: string, isFinal: boolean) => void): Promise<void> {
    SpeechRecognizerManager.resultCallback = callback;
    try {
      const extraParam: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'long' };
      const createParams: Record<string, Object> = {
        'language': 'zh-CN',
        'online': 1,
        'extraParams': extraParam
      };
      SpeechRecognizerManager.asrEngine = await speechRecognizer.createEngine(createParams);
      const engine = SpeechRecognizerManager.asrEngine as Record<string, Function>;

      const listener: Record<string, Function> = {
        'onStart': (_sid: string, _msg: string) => {
          SpeechRecognizerManager.isListening = true;
        },
        'onEvent': (_sid: string, _code: number, _msg: string) => {},
        'onResult': (_sid: string, result: Record<string, Object>) => {
          const isFinal = result['isFinal'] as boolean;
          const text = result['result'] as string;
          if (SpeechRecognizerManager.resultCallback) {
            SpeechRecognizerManager.resultCallback(text, isFinal);
          }
        },
        'onComplete': (_sid: string, _msg: string) => {
          SpeechRecognizerManager.isListening = false;
        },
        'onError': (_sid: string, code: number, msg: string) => {
          SpeechRecognizerManager.isListening = false;
          console.error('语音识别错误:', code, msg);
        }
      };
      engine['setListener'](listener);

      const audioParams: Record<string, Object> = {
        'sessionId': SpeechRecognizerManager.sessionId,
        'audioInfo': {
          'audioType': 'pcm',
          'sampleRate': 16000,
          'soundChannel': 1,
          'sampleBit': 16
        },
        'extraParams': {
          'recognitionMode': 0,
          'maxAudioDuration': 60000
        }
      };
      engine['startListening'](audioParams);
    } catch (err) {
      console.error('语音引擎初始化失败:', JSON.stringify(err));
    }
  }

  static async release(): Promise<void> {
    try {
      const engine = SpeechRecognizerManager.asrEngine as Record<string, Function> | null;
      if (engine) {
        engine['cancel'](SpeechRecognizerManager.sessionId);
        engine['shutdown']();
      }
    } catch (_e) {}
    SpeechRecognizerManager.asrEngine = null;
    SpeechRecognizerManager.isListening = false;
    SpeechRecognizerManager.resultCallback = null;
  }
}

export default SpeechRecognizerManager;
```

---

## 步骤 3：新建文件 `entry/src/main/ets/utils/SportVoiceParser.ets`

```typescript
const SPORT_KEYWORDS: Record<string, string> = {
  '跑步': '跑步', '跑': '跑步',
  '游泳': '游泳', '游': '游泳',
  '骑行': '骑行', '骑': '骑行',
  '健身': '健身',
  '瑜伽': '瑜伽',
  '跳绳': '跳绳',
  '走路': '走路', '散步': '走路',
  '篮球': '篮球',
  '足球': '足球',
  '羽毛球': '羽毛球',
  '乒乓球': '乒乓球',
  '爬山': '爬山', '登山': '爬山',
  '徒步': '徒步'
};

export interface ParsedSportRecord {
  name: string;
  duration: number;
  calories: number;
}

export class SportVoiceParser {
  static parse(text: string): ParsedSportRecord | null {
    if (!text || text.length < 2) {
      return null;
    }

    let sportName = '运动';
    const keys = Object.keys(SPORT_KEYWORDS);
    for (let i = 0; i < keys.length; i++) {
      if (text.includes(keys[i])) {
        sportName = SPORT_KEYWORDS[keys[i]];
        break;
      }
    }

    let duration = 0;
    const durationPatterns: Array<RegExp> = [
      /(\d+)\s*(分钟|min)/i,
      /(\d+)\s*分/,
      /(\d+\.?\d*)\s*(小时|h|hour)/i
    ];
    for (let i = 0; i < durationPatterns.length; i++) {
      const match = text.match(durationPatterns[i]);
      if (match) {
        if (match[2] === '小时' || match[2] === 'h' || match[2] === 'hour') {
          duration = Math.round(parseFloat(match[1]) * 60);
        } else {
          duration = parseInt(match[1]);
        }
        break;
      }
    }
    if (duration === 0) {
      duration = 30;
    }

    let calories = 0;
    const calPatterns: Array<RegExp> = [
      /(\d+)\s*(千卡|卡路里|卡|kcal|大卡)/i,
      /消耗[了]?\s*(\d+)/
    ];
    for (let i = 0; i < calPatterns.length; i++) {
      const match = text.match(calPatterns[i]);
      if (match) {
        calories = parseInt(match[1]);
        break;
      }
    }

    return { name: sportName, duration: duration, calories: calories };
  }
}
```

---

## 步骤 4：改 `entry/src/main/module.json5`

### 4.1 找到 `requestPermissions` 数组

当前内容（约第 13-22 行）：

```json5
    "requestPermissions": [
      {
        "name": "ohos.permission.PUBLISH_AGENT_REMINDER",
        "reason": "$string:notification_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "always"
        },
      }
    ],
```

### 4.2 把 `}` （第 8 行那个）改成 `},` 并在下一行插入

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

### 4.3 最终结果

```json5
    "requestPermissions": [
      {
        "name": "ohos.permission.PUBLISH_AGENT_REMINDER",
        "reason": "$string:notification_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "always"
        },
      },
      {
        "name": "ohos.permission.MICROPHONE",
        "reason": "$string:voice_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "inuse"
        }
      }
    ],
```

---

## 步骤 5：改 `entry/src/main/resources/base/element/string.json`

在 `notification_reason` 那条结束后（第 16-18 行），加逗号 + 新条目：

```json
    {
      "name": "notification_reason",
      "value": "用于在运动完成后推送完成通知"
    },
    {
      "name": "voice_reason",
      "value": "用于语音记录您的运动数据"
    }
```

---

## 步骤 6：改 `entry/src/main/ets/pages/Index.ets`

### 6.1 顶部加 3 行 import

找到第 4 行 `import { batteryInfo } from '@kit.BasicServicesKit';`，在它**下面**插入 3 行：

```typescript
import { batteryInfo } from '@kit.BasicServicesKit';
import { PermissionManager } from '../utils/PermissionManager';
import SpeechRecognizerManager from '../utils/SpeechRecognizerManager';
import { SportVoiceParser } from '../utils/SportVoiceParser';
```

### 6.2 替换 AIVoiceDialog 整个 struct

找到 `@Component struct AIVoiceDialog {` 这一行（约第 1570 行），把**从这行开始到结尾的 `}`**（代码块最后一个 `}`） 全部删掉。

搜索关键字 `@Component struct AIVoiceDialog` 定位起点，然后删到它的结束 `}`，替换为以下内容：

```typescript
@Component
struct AIVoiceDialog {
  onClose: () => void = () => {};
  onConfirm: (type: string, duration: number, calories: number) => void = () => {};

  @State isRecording: boolean = false;
  @State fullVoiceText: string = '';
  @State parsedSport: string = '';
  @State parsedDuration: number = 1;
  @State parsedCalories: number = 0;
  @State hasPermission: boolean = false;

  aboutToAppear() {
    this.checkPerm();
  }

  aboutToDisappear() {
    SpeechRecognizerManager.release();
  }

  async checkPerm() {
    const ok = PermissionManager.checkPermission('ohos.permission.MICROPHONE');
    if (ok) {
      this.hasPermission = true;
    } else {
      this.hasPermission = await PermissionManager.requestPermission('ohos.permission.MICROPHONE');
    }
  }

  async toggleRecord() {
    if (!this.hasPermission) {
      return;
    }
    if (!this.isRecording) {
      this.fullVoiceText = '';
      this.parsedSport = '';
      this.parsedDuration = 1;
      this.parsedCalories = 0;
      await SpeechRecognizerManager.init((text: string, isFinal: boolean) => {
        this.fullVoiceText = text;
        if (isFinal && text.length > 0) {
          const result = SportVoiceParser.parse(text);
          if (result) {
            this.parsedSport = result.name;
            this.parsedDuration = result.duration;
            this.parsedCalories = result.calories;
          }
        }
      });
      this.isRecording = true;
    } else {
      await SpeechRecognizerManager.release();
      this.isRecording = false;
      if (this.fullVoiceText.length > 0 && !this.parsedSport) {
        const result = SportVoiceParser.parse(this.fullVoiceText);
        if (result) {
          this.parsedSport = result.name;
          this.parsedDuration = result.duration;
          this.parsedCalories = result.calories;
        }
      }
    }
  }

  confirmAdd() {
    if (!this.parsedSport) {
      return;
    }
    this.onConfirm(this.parsedSport, this.parsedDuration, this.parsedCalories);
    SpeechRecognizerManager.release();
  }

  build() {
    Column() {
      Column() {
        Row() {
          Text('← 返回')
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              SpeechRecognizerManager.release();
              this.onClose();
            })
        }
        .width('100%')
        .padding({ top: 16, bottom: 8 })

        Text('AI 语音记录运动')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 6 })

        Text(this.hasPermission ? '✅ 权限就绪' : '⚠ 需要麦克风权限')
          .fontSize(12)
          .fontColor(this.hasPermission ? '#36C960' : '#F5A623')
          .margin({ bottom: 16 })

        Column() {
          Text(this.isRecording ? '🔴' : '🎙')
            .fontSize(64)
        }
        .width(140)
        .height(140)
        .borderRadius(70)
        .backgroundColor(this.isRecording ? '#FFF0F0' : $r('app.color.background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 12 })

        Text(this.isRecording ? '正在收音，请说话...' : '点击下方按钮开始录音')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 20 })

        Button(this.isRecording ? '结束录音' : '开始录音')
          .fontSize(16)
          .fontColor($r('app.color.surface'))
          .fontWeight(FontWeight.Medium)
          .width('80%')
          .height(48)
          .borderRadius(24)
          .enabled(this.hasPermission)
          .linearGradient({
            angle: 90,
            colors: [[$r('app.color.gradient_start'), 0], [$r('app.color.gradient_end'), 1]]
          })
          .opacity(this.hasPermission ? 1 : 0.4)
          .margin({ bottom: 16 })
          .onClick(() => { this.toggleRecord(); })

        if (this.fullVoiceText.length > 0) {
          Column() {
            Text('识别原文：')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 4 })
            Text(this.fullVoiceText)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .padding(8)
              .backgroundColor($r('app.color.background'))
              .borderRadius(8)
          }
          .width('100%')
          .margin({ bottom: 12 })
        }

        if (this.parsedSport) {
          Row({ space: 8 }) {
            Text(this.parsedSport)
              .fontSize(12)
              .fontColor($r('app.color.surface'))
              .backgroundColor($r('app.color.primary'))
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            Text(`${this.parsedDuration}分钟`)
              .fontSize(12)
              .fontColor($r('app.color.surface'))
              .backgroundColor('#F5A623')
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            if (this.parsedCalories > 0) {
              Text(`${this.parsedCalories}千卡`)
                .fontSize(12)
                .fontColor($r('app.color.surface'))
                .backgroundColor('#E53E3E')
                .borderRadius(4)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            }
          }
          .width('100%')
          .margin({ bottom: 16 })
        }

        Button('确认添加')
          .fontSize(15)
          .fontColor($r('app.color.surface'))
          .fontWeight(FontWeight.Medium)
          .width('80%')
          .height(44)
          .borderRadius(22)
          .enabled(this.parsedSport.length > 0)
          .backgroundColor(this.parsedSport.length > 0 ? '#36C960' : $r('app.color.divider'))
          .margin({ bottom: 16 })
          .onClick(() => { this.confirmAdd(); })

        Text('💡 尝试说 "我刚跑步 20 分钟，消耗 150 千卡"')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 16 })
      }
      .width('85%')
      .padding({ left: 20, right: 20 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      SpeechRecognizerManager.release();
      this.onClose();
    })
  }
}
```

---

## 步骤 7：验证

改完后在 DevEco Studio 里：
1. Build → Clean Project
2. Build → Rebuild
3. 确认 0 编译错误
4. 模拟器卸载 App → 重新安装
5. 点「AI语音添加运动」→ 系统弹麦克风授权 → 允许
6. 点「开始录音」→ 说话 → 识别完成后彩色色块显示运动/分钟/千卡
7. 点「确认添加」→ 记录写入

---

## 回退方式

把以下 5 个位置还原即可：
- 删掉 `ets/utils/` 下 3 个文件
- `module.json5` 删掉 MICROPHONE 权限那段
- `string.json` 删掉 voice_reason 那条
- `Index.ets` import 删掉新增的 3 行
- `Index.ets` AIVoiceDialog 改回原来的模拟版
