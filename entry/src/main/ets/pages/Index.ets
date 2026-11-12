import { SportDataManager, SportRecord } from '../data/SportDataManager';
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { PermissionManager } from '../utils/PermissionManager';
import SpeechRecognizerManager from '../utils/SpeechRecognizerManager';
import { SportVoiceParser } from '../utils/SportVoiceParser';

interface AddRecordDialogParams {
  selectedDate: string;
  onClose: () => void;
  onConfirm: (record: SportRecord) => void;
}

interface AIVoiceDialogParams {
  onClose: () => void;
  onConfirm: (type: string, duration: number, calories: number) => void;
}

interface NotifyBasic {
  title: string;
  text: string;
}

interface NotifyContent {
  notificationContentType: number;
  normal: NotifyBasic;
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State todayRefresh: number = 0;
  @StorageLink('navigateTab') @Watch('onNavigateTab') navigateTab: number = 0;
  @StorageLink('dataChanged') @Watch('onDataChanged') dataChanged: number = 0;
  private tabsController: TabsController = new TabsController();
  // 由父组件统一计算，直接传给 ProfilePage，绕过 TabContent 生命周期问题
  @State profileTotalCount: number = 0;
  @State profileTotalDuration: number = 0;
  @State profileTotalCalories: number = 0;
  @State profileWeekDays: number = 0;
  @State profileWeekDuration: number = 0;
  @State profileWeekProgress: number = 0;
  @State profileWeekRange: string = '';

  aboutToAppear() {
    AppStorage.setOrCreate('dataChanged', 0);
    AppStorage.setOrCreate('navigateTab', -1);
    this.refreshProfileStats();
  }

  refreshProfileStats() {
    const mgr = SportDataManager.getInstance();
    const allRecords = mgr.getRecords();
    const completed = allRecords.filter(r => r.completed);
    this.profileTotalCount = completed.length;
    this.profileTotalDuration = completed.reduce((s, r) => s + r.duration, 0);
    this.profileTotalCalories = completed.reduce((s, r) => s + r.calories, 0);

    const now = new Date();
    const dow = now.getDay();
    const start = new Date(now);
    start.setDate(now.getDate() - dow + (dow === 0 ? -6 : 1));
    const days: Date[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(start);
      d.setDate(start.getDate() + i);
      days.push(d);
    }
    this.profileWeekRange = `${mgr.formatDate(days[0])} ~ ${mgr.formatDate(days[6])}`;
    const weekRecords = mgr.getWeekRecords(days).filter(r => r.completed);
    const daySet = new Set(weekRecords.map(r => r.sport_date));
    this.profileWeekDays = daySet.size;
    this.profileWeekDuration = weekRecords.reduce((s, r) => s + r.duration, 0);
    this.profileWeekProgress = Math.min(100, Math.floor(this.profileWeekDuration * 100 / 150));
  }

  onDataChanged() {
    this.todayRefresh++;
    this.refreshProfileStats();
  }

  onNavigateTab() {
    if (this.navigateTab >= 0) {
      this.currentIndex = this.navigateTab;
      this.tabsController.changeIndex(this.navigateTab);
      this.todayRefresh++;
      AppStorage.set('navigateTab', -1);
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() {
        SportRecordPage({ refreshTrigger: this.todayRefresh })
      }
      .tabBar(this.TabBarBuilder('运动记录', 0))

      TabContent() {
        TodaySportPage({ refreshTrigger: this.todayRefresh })
      }
      .tabBar(this.TabBarBuilder('今日运动', 1))

      TabContent() {
        ProfilePage({
          totalCount: this.profileTotalCount,
          totalDuration: this.profileTotalDuration,
          totalCalories: this.profileTotalCalories,
          weekDays: this.profileWeekDays,
          weekDuration: this.profileWeekDuration,
          weekProgress: this.profileWeekProgress,
          weekRange: this.profileWeekRange
        })
      }
      .tabBar(this.TabBarBuilder('我的', 2))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    .onChange((index: number) => {
      this.currentIndex = index;
      AppStorage.set('dataChanged', Date.now());
    })
  }

  @Builder
  TabBarBuilder(title: string, targetIndex: number) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor(this.currentIndex === targetIndex ? $r('app.color.primary') : $r('app.color.text_secondary'))
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = targetIndex;
      this.tabsController.changeIndex(targetIndex);
      if (targetIndex === 1 || targetIndex === 0 || targetIndex === 2) {
        this.todayRefresh++;
      }
      // 切到"我的"标签时强制通知 ProfilePage 刷新统计数据
      if (targetIndex === 2) {
        AppStorage.set('dataChanged', Date.now());
      }
    })
  }
}

@Component
struct SportRecordPage {
  @Prop @Watch('loadWeekRecords') refreshTrigger: number = 0;
  @State currentWeek: Date = new Date();
  @State recordList: SportRecord[] = [];
  @State showAddDialog: boolean = false;
  @State showDatePicker: boolean = false;

  aboutToAppear() {
    this.loadWeekRecords();
  }

  loadWeekRecords() {
    this.recordList = SportDataManager.getInstance().getWeekRecords(this.getWeekDays());
  }

  getWeekDays(): Date[] {
    const days: Date[] = [];
    const startOfWeek = new Date(this.currentWeek);
    const day = startOfWeek.getDay();
    const diff = startOfWeek.getDate() - day + (day === 0 ? -6 : 1);
    startOfWeek.setDate(diff);
    for (let i = 0; i < 7; i++) {
      const d = new Date(startOfWeek);
      d.setDate(startOfWeek.getDate() + i);
      days.push(d);
    }
    return days;
  }

  getWeekRangeText(): string {
    const days = this.getWeekDays();
    const start = days[0];
    const end = days[6];
    const m1 = String(start.getMonth() + 1).padStart(2, '0');
    const d1 = String(start.getDate()).padStart(2, '0');
    const m2 = String(end.getMonth() + 1).padStart(2, '0');
    const d2 = String(end.getDate()).padStart(2, '0');
    return `${start.getFullYear()}-${m1}-${d1} ~ ${m2}-${d2}`;
  }

  build() {
    Stack() {
      Column() {
        Text('本周运动记录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 16, top: 16 })

        Row() {
          Button(this.getWeekRangeText())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showDatePicker = true;
            })
          Blank()
          Button('+ 添加')
            .fontSize(13)
            .fontColor($r('app.color.surface'))
            .backgroundColor($r('app.color.primary'))
            .height(28)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.showAddDialog = true;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

        Row() {
          Text(`本周共 ${this.recordList.length} 条运动记录`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        Row() {
          ForEach(this.getWeekDays(), (day: Date) => {
            Column() {
              Text(['一', '二', '三', '四', '五', '六', '日'][day.getDay() === 0 ? 6 : day.getDay() - 1])
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Text(String(day.getDate()))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .height(50)
            .justifyContent(FlexAlign.Center)
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 12 })

        Grid() {
          ForEach(this.getWeekDays(), (day: Date) => {
            GridItem() {
              Column() {
                ForEach(this.recordList.filter(r => r.sport_date === SportDataManager.getInstance().formatDate(day)), (record: SportRecord) => {
                  Row() {
                    Text(record.sport_name)
                      .fontSize(12)
                      .fontColor($r('app.color.surface'))
                  }
                  .backgroundColor(record.sport_name === '跑步' ? $r('app.color.card_running') : 
                                   record.sport_name === '游泳' ? $r('app.color.card_swimming') :
                                   record.sport_name === '户外散步' ? $r('app.color.card_walking') :
                                   record.sport_name === '室内健身' ? $r('app.color.card_fitness') : $r('app.color.accent_blue'))
                  .borderRadius(4)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .margin({ top: 4 })
                  .opacity(record.completed ? 0.5 : 1)
                })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Start)
              .padding({ top: 8 })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr')
        .columnsGap(4)
        .backgroundColor($r('app.color.background'))
      }
      .width('100%')
      .height('100%')

      if (this.showAddDialog) {
        AddRecordDialog({
          selectedDate: SportDataManager.getInstance().formatDate(new Date()),
          onClose: () => { this.showAddDialog = false; },
          onConfirm: async (record: SportRecord) => {
            try {
              await SportDataManager.getInstance().addRecord(record);
              this.showAddDialog = false;
              this.loadWeekRecords();
              AppStorage.set('dataChanged', Date.now());
            } catch (err) {
              console.error('添加运动记录失败:', JSON.stringify(err));
            }
          }
        } as AddRecordDialogParams)
      }

      if (this.showDatePicker) {
        Column() {
          Column() {
            DatePicker({
              start: new Date('2020-01-01'),
              end: new Date('2030-12-31'),
              selected: this.currentWeek
            })
              .onChange((value: DatePickerResult) => {
                this.currentWeek = new Date(value.year as number, (value.month as number), value.day as number);
              })

            Row() {
              Button('取消')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.background'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .margin({ right: 12 })
                .onClick(() => { this.showDatePicker = false; })

              Button('确定')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor($r('app.color.primary'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .onClick(() => {
                  this.loadWeekRecords();
                  this.showDatePicker = false;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          }
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .padding({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct TodaySportPage {
  @Prop @Watch('loadRecords') refreshTrigger: number = 0;
  @State selectedDate: Date = new Date();
  @State todayRecords: SportRecord[] = [];
  @State selectedRecords: SportRecord[] = [];
  @State selectDuration: number = 0;
  @State selectCalories: number = 0;
  @State todayTotalDuration: number = 0;
  @State todayTotalCalories: number = 0;
  @State showAIVoice: boolean = false;
  @State showDatePicker: boolean = false;
  @State showReminder: boolean = false;
  @State reminderOn: boolean = false;

  @State isRunning: boolean = false;
  @State isPaused: boolean = false;
  @State currentSportType: string = '';
  @State remainingTime: number = 0;
  @State elapsedCalories: number = 0;
  private timer: number | null = null;

  aboutToAppear() {
    this.loadRecords();
  }

  aboutToDisappear() {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.isRunning = false;
    this.isPaused = false;
  }

  loadRecords() {
    const mgr = SportDataManager.getInstance();
    const dateStr = mgr.formatDate(this.selectedDate);
    const all = mgr.getRecordsByDate(dateStr);
    this.todayRecords = all.map(r => new SportRecord(r.id, r.sport_name, r.duration, r.calories, r.sport_date, r.create_time, r.completed));
    this.selectedRecords = [];
    this.selectDuration = 0;
    this.selectCalories = 0;
    this.todayTotalDuration = all.reduce((s, r) => s + r.duration, 0);
    this.todayTotalCalories = all.reduce((s, r) => s + r.calories, 0);
  }

  isRecordSelected(record: SportRecord): boolean {
    return this.selectedRecords.some(r => r.id === record.id);
  }

  toggleRecord(record: SportRecord) {
    if (this.isRunning) return;
    const idx = this.selectedRecords.findIndex(r => r.id === record.id);
    if (idx > -1) {
      this.selectedRecords.splice(idx, 1);
    } else {
      this.selectedRecords.push(record);
    }
    this.selectDuration = this.selectedRecords.reduce((sum: number, r: SportRecord) => sum + r.duration, 0);
    this.selectCalories = this.selectedRecords.reduce((sum: number, r: SportRecord) => sum + r.calories, 0);
  }

  formatSelectedDate(): string {
    const d = this.selectedDate;
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${m}-${day}`;
  }

  getTimeText(): string {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }

  formatTime(seconds: number): string {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (hours > 0) {
      return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  startExercise() {
    if (this.timer) return;
    if (this.selectedRecords.length === 0) {
      AlertDialog.show({
        title: '提示',
        message: '请至少选择一项运动记录',
        confirm: { value: '确定', action: () => {} }
      });
      return;
    }

    this.isRunning = true;
    this.isPaused = false;
    this.currentSportType = this.selectedRecords.map(r => r.sport_name).join(' + ');
    this.remainingTime = this.selectDuration * 60;
    this.elapsedCalories = 0;

    const caloriesPerSec = this.selectedRecords.length > 0 && this.selectDuration > 0
      ? this.selectCalories / (this.selectDuration * 60) : 0;
    const totalDurationSec = this.selectDuration * 60;

    const timerId = setInterval(() => {
      if (!this.isPaused && this.remainingTime > 0) {
        this.remainingTime--;
        const elapsedSec = totalDurationSec - this.remainingTime;
        this.elapsedCalories = Math.round(elapsedSec * caloriesPerSec);
      }
      if (this.remainingTime <= 0 && this.isRunning && !this.isPaused) {
        this.endExercise();
      }
    }, 1000);
    this.timer = timerId as number;
  }

  pauseExercise() {
    this.isPaused = !this.isPaused;
  }

  async endExercise() {
    if (!this.timer && !this.isRunning) return;

    const completed = this.remainingTime <= 0;
    const finishedCalories = this.elapsedCalories;
    const finishedDuration = this.selectDuration;
    const finishedType = this.currentSportType;

    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }

    this.isRunning = false;
    this.isPaused = false;

    if (this.selectedRecords.length > 0) {
      const mgr = SportDataManager.getInstance();
      const allRecords = mgr.getRecords();
      const completedIds = new Set(this.selectedRecords.map(sr => sr.id));
      allRecords.forEach(r => {
        if (completedIds.has(r.id)) { r.completed = true; }
      });
      try {
        await mgr.save();
      } catch (err) {
        console.error('保存运动记录失败:', JSON.stringify(err));
      }
      this.loadRecords();
      AppStorage.set('dataChanged', Date.now());
    }

    this.selectedRecords = [];
    this.selectDuration = 0;
    this.selectCalories = 0;
    this.remainingTime = 0;
    this.elapsedCalories = 0;
    this.currentSportType = '';

    if (completed || finishedCalories > 0) {
      this.sendNotification('运动已完成', `${finishedType}\n${finishedDuration}分钟 · ${finishedCalories}千卡`);
    }
  }

  async sendNotification(title: string, text: string) {
    try {
      const isEnabled = await notificationManager.isNotificationEnabled();
      if (!isEnabled) {
        // 通知未开启，引导用户开启
        await notificationManager.requestEnableNotification();
        const recheck = await notificationManager.isNotificationEnabled();
        if (!recheck) {
          console.info('通知权限未开启，跳过发送');
          return;
        }
      }
    } catch (_e) {
      console.info('通知权限检查失败，尝试直接发送');
    }

    const bundleName = AppStorage.get<string>('appBundleName') ?? 'com.example.sporhealthhelper';
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: bundleName,
        abilityName: 'EntryAbility',
        parameters: { targetTab: '1' }
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(wantAgentInfo, (err, agent) => {
      if (err) {
        console.error('wantAgent 创建失败:', JSON.stringify(err));
        return;
      }
      const basic: NotifyBasic = { title: title, text: text };
      const content: NotifyContent = {
        notificationContentType: 0,
        normal: basic
      };
      const request = {
        id: Date.now(),
        content: content,
        wantAgent: agent,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      } as notificationManager.NotificationRequest;
      notificationManager.publish(request, (pubErr) => {
        if (pubErr) {
          console.error('通知发送失败:', JSON.stringify(pubErr));
        } else {
          console.info('通知发送成功:', title);
        }
      });
    });
  }

  showReminderDialog() {
    this.showReminder = true;
  }

  toggleReminder() {
    this.reminderOn = !this.reminderOn;
    if (this.reminderOn) {
      this.sendNotification('运动提醒', '记得按时运动，保持健康生活！');
    }
  }

  deleteRecord(record: SportRecord) {
    if (record.completed) {
      AlertDialog.show({
        title: '确认删除',
        message: `确定要删除「${record.sport_name}」吗？\n该记录已标记为已完成`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '确认删除',
          fontColor: '#E74C3C',
          action: () => {
            SportDataManager.getInstance().deleteRecord(record.id).then(() => {
              this.loadRecords();
              AppStorage.set('dataChanged', Date.now());
            });
          }
        }
      });
      return;
    }
    SportDataManager.getInstance().deleteRecord(record.id).then(() => {
      this.loadRecords();
      AppStorage.set('dataChanged', Date.now());
    }).catch((err: Error) => {
      console.error('删除运动记录失败:', JSON.stringify(err));
    });
  }

  completeRecord(record: SportRecord) {
    const mgr = SportDataManager.getInstance();
    const original = mgr.getRecords().find(r => r.id === record.id);
    if (original) { original.completed = true; }
    this.sendNotification('运动已完成', `${record.sport_name}\n${record.duration}分钟 · ${record.calories}千卡`);
    mgr.save().then(() => {
      this.loadRecords();
      AppStorage.set('dataChanged', Date.now());
    }).catch((err: Error) => {
      console.error('保存运动记录失败:', JSON.stringify(err));
    });
  }

  build() {
    Stack() {
      Column() {
        Column() {
          Button(this.formatSelectedDate())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.showDatePicker = true; })
          
          Row() {
            Text('🕐')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(this.getTimeText())
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })
            Blank()
            Text('🔋')
              .fontSize(14)
            Text(`${batteryInfo.batterySOC}%`)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .width('100%')
          .margin({ top: 8 })

          if (this.isRunning) {
            Column() {
              Text(this.currentSportType)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
                .margin({ bottom: 8 })
              
              Text(this.formatTime(this.remainingTime))
                .fontSize(48)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.isPaused ? $r('app.color.text_secondary') : $r('app.color.primary'))
              
              Text(`${this.elapsedCalories}千卡`)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .margin({ top: 12 })
            .padding({ top: 16, bottom: 16 })
            .backgroundColor($r('app.color.primary_light'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .backgroundColor($r('app.color.surface'))

        if (this.todayRecords.length === 0) {
          Column() {
            Text('🏃‍♂️')
              .fontSize(60)
              .margin({ bottom: 16 })
            Text('今天还没有运动记录')
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .margin({ bottom: 8 })
            Text('添加你的第一次运动吧')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            ForEach(this.todayRecords, (record: SportRecord) => {
              SwipeRecordItem({
                record: record,
                isSelected: this.isRecordSelected(record),
                completed: record.completed,
                disabled: this.isRunning,
                onDelete: () => { this.deleteRecord(record); },
                onComplete: () => { this.completeRecord(record); },
                onToggle: () => { this.toggleRecord(record); }
              })
            }, (record: SportRecord): string => `${record.id}-${record.completed}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 12 })
        }

        Column() {
          if (!this.isRunning) {
            Row() {
              Button('开始运动')
                .fontSize(15)
                .fontColor($r('app.color.surface'))
                .backgroundColor(this.selectedRecords.length > 0 ? $r('app.color.primary') : $r('app.color.text_hint'))
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .onClick(() => { this.startExercise(); })

              Button(this.reminderOn ? '🔔 已开启提醒' : '🔔 发送提醒')
                .fontSize(15)
                .fontColor($r('app.color.surface'))
                .backgroundColor(this.reminderOn ? $r('app.color.accent_green') : $r('app.color.accent_blue'))
                .layoutWeight(1)
                .height(48)
                .borderRadius(24)
                .margin({ left: 12 })
                .onClick(() => { this.toggleReminder(); })
            }
            .width('100%')
            .margin({ bottom: 10 })
          } else {
            Row() {
              Button('⏸ 暂停')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor(this.isPaused ? $r('app.color.primary') : $r('app.color.accent_orange'))
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .onClick(() => { this.pauseExercise(); })

              Button('⏹ 结束运动')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor($r('app.color.error'))
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .margin({ left: 10 })
                .onClick(() => { this.endExercise(); })
            }
            .width('100%')
            .margin({ bottom: 10 })
          }

          Button() {
            Row() {
              Text('🎤')
                .fontSize(18)
              Text('AI语音添加运动')
                .fontSize(15)
                .fontColor($r('app.color.surface'))
                .fontWeight(FontWeight.Medium)
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .height(50)
          .borderRadius(25)
          .linearGradient({
            angle: 90,
            colors: [[$r('app.color.gradient_start'), 0], [$r('app.color.gradient_end'), 1]]
          })
          .onClick(() => {
            this.showAIVoice = true;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .backgroundColor($r('app.color.surface'))
      }
      .width('100%')
      .height('100%')

      if (this.showAIVoice) {
        AIVoiceDialog({
          onClose: () => { this.showAIVoice = false; },
          onConfirm: (type: string, duration: number, calories: number) => {
            const record = new SportRecord(
              String(Date.now()),
              type,
              duration,
              calories,
              SportDataManager.getInstance().formatDate(new Date()),
              SportDataManager.getInstance().formatDateTime(new Date())
            );
            SportDataManager.getInstance().addRecord(record).then(() => {
              this.loadRecords();
              this.showAIVoice = false;
              AppStorage.set('dataChanged', Date.now());
            }).catch((err: Error) => {
              console.error('添加运动记录失败:', JSON.stringify(err));
            });
          }
        } as AIVoiceDialogParams)
      }

      if (this.showDatePicker) {
        Column() {
          Column() {
            DatePicker({
              start: new Date('2020-01-01'),
              end: new Date('2030-12-31'),
              selected: this.selectedDate
            })
              .onChange((value: DatePickerResult) => {
                this.selectedDate = new Date(value.year as number, (value.month as number), value.day as number);
              })

            Row() {
              Button('取消')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.background'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .margin({ right: 12 })
                .onClick(() => { this.showDatePicker = false; })

              Button('确定')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor($r('app.color.primary'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .onClick(() => {
                  this.loadRecords();
                  this.showDatePicker = false;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          }
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .padding({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {})
      }

      if (this.showReminder) {
        Column() {
          Column() {
            Text('🔔')
              .fontSize(48)
              .margin({ bottom: 12 })
            Text('运动提醒')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('记得按时运动，保持健康生活！')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 8 })

            Button('知道了')
              .fontSize(14)
              .fontColor($r('app.color.surface'))
              .backgroundColor($r('app.color.primary'))
              .width('100%')
              .height(44)
              .borderRadius(22)
              .margin({ top: 20 })
              .onClick(() => { this.showReminder = false; })
          }
          .width('280px')
          .padding({ left: 24, right: 24, top: 32, bottom: 32 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(20)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
  }
}


@Component
struct SwipeRecordItem {
  record: SportRecord = new SportRecord('', '', 0, 0, '', '');
  @State offsetX: number = 0;
  @State private gestureStartX: number = 0;
  isSelected: boolean = false;
  completed: boolean = false;
  disabled: boolean = false;
  onDelete: () => void = () => {};
  onComplete: () => void = () => {};
  onToggle: () => void = () => {};

  build() {
    Row() {
      Row() {
        Column() {
          Row({ space: 6 }) {
            Text(this.record.sport_name)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            if (this.completed) {
              Text('已完成')
                .fontSize(10)
                .fontColor($r('app.color.surface'))
                .backgroundColor('#4CAF50')
                .borderRadius(4)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
          }
          Text(`${this.record.duration}分钟 · ${this.record.calories}千卡`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.completed) {
          Text(this.isSelected ? '✓' : '○')
            .fontSize(20)
            .fontColor(this.isSelected ? $r('app.color.primary') : $r('app.color.text_hint'))
        } else {
          Text('✓')
            .fontSize(22)
            .fontColor('#4CAF50')
            .fontWeight(FontWeight.Bold)
        }
      }
      .height(60)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.isSelected ? $r('app.color.primary_light') : $r('app.color.surface'))
      .borderRadius(12)
      .layoutWeight(1)
      .onClick(() => {
        if (this.disabled || this.completed) return;
        if (this.offsetX < 0) {
          this.offsetX = 0;
        } else {
          this.onToggle();
        }
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 5 })
          .onActionStart(() => {
            this.gestureStartX = this.offsetX;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.disabled || this.completed) return;
            const newOffset = this.gestureStartX + event.offsetX;
            this.offsetX = Math.max(-128, Math.min(0, newOffset));
          })
          .onActionEnd(() => {
            if (this.offsetX < -60) {
              this.offsetX = -128;
            } else {
              this.offsetX = 0;
            }
          })
      )

      Column() {
        if (!this.completed) {
          Button('已完成')
            .fontSize(12)
            .fontColor(Color.White)
            .backgroundColor('#4CAF50')
            .width(64)
            .height(30)
            .borderRadius(6)
            .margin({ bottom: 4 })
            .onClick(() => {
              this.offsetX = 0;
              this.onComplete();
            })
        }
        Button('删除')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#E74C3C')
          .width(64)
          .height(this.completed ? 60 : 30)
          .borderRadius(6)
          .onClick(() => {
            this.offsetX = 0;
            this.onDelete();
          })
      }
      .width(this.offsetX < -60 ? 72 : 0)
      .height(60)
      .justifyContent(this.completed ? FlexAlign.Center : FlexAlign.Start)
      .padding({ left: this.offsetX < -60 ? 8 : 0 })
      .animation({ duration: 200, curve: Curve.Ease })
      .clip(true)
    }
    .width('100%')
    .height(60)
    .margin({ bottom: 8 })
  }
}

// ==================== 我的页面 ====================

@Component
struct ProfilePage {
  @Prop totalCount: number = 0;
  @Prop totalDuration: number = 0;
  @Prop totalCalories: number = 0;
  @Prop weekDays: number = 0;
  @Prop weekDuration: number = 0;
  @Prop weekProgress: number = 0;
  @Prop weekRange: string = '';
  @State showClearConfirm: boolean = false;
  @State currentWeek: Date = new Date();
  @State showWeekDatePicker: boolean = false;

  clearAllData() {
    this.showClearConfirm = true;
  }

  confirmClearData() {
    SportDataManager.getInstance().clearAll().then(() => {
      this.showClearConfirm = false;
      AppStorage.set('dataChanged', Date.now());
    }).catch((err: Error) => {
      console.error('清除数据失败:', JSON.stringify(err));
      this.showClearConfirm = false;
    });
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          // ===== 用户卡片 =====
          Column() {
            Row({ space: 16 }) {
              Column() {
                Text('🏃‍♂️')
                  .fontSize(36)
              }
              .width(72)
              .height(72)
              .borderRadius(36)
              .backgroundColor($r('app.color.primary_light'))
              .justifyContent(FlexAlign.Center)

              Column() {
                Text('运动达人')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 4 })
                Text('运动健康助手')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text('坚持运动，保持健康 💪')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 20, bottom: 20 })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 12 })

          // ===== 总览三栏 =====
          Row() {
            Column({ space: 4 }) {
              Text(String(this.totalCount))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('总次数')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.totalDuration}分钟`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#F5A623')
              Text('总时长')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)

            Column({ space: 4 }) {
              Text(`${this.totalCalories}卡`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor('#E53E3E')
              Text('总消耗')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 12 })

          // ===== 本周运动进度 =====
          Column() {
            Row() {
              Text('本周运动')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.weekDays}天`)
                .fontSize(13)
                .fontColor('#36C960')
            }
            .width('100%')

            Text(this.weekRange)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2, bottom: 12 })
              .onClick(() => { this.showWeekDatePicker = true; })

            Row() {
              Text(`本周运动 ${this.weekDuration}分钟`)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Row({ space: 4 }) {
                Text('⚠')
                  .fontSize(12)
                Text('建议150分钟/周')
                  .fontSize(11)
                  .fontColor('#F5A623')
              }
            }
            .width('100%')

            Row({ space: 8 }) {
              Text(`进度 ${this.weekProgress}%`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Stack() {
                Rect()
                  .width('100%')
                  .height(8)
                  .fill($r('app.color.divider'))
                  .borderRadius(4)
                Rect()
                  .width(`${this.weekProgress}%`)
                  .height(8)
                  .fill('#36C960')
                  .borderRadius(4)
              }
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 12 })

          // ===== 设置 =====
          Text('设置')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 8 })

          Column() {
            this.SettingRow('🔔', '通知设置', '管理运动提醒推送', () => {})
            this.SettingRow('ℹ', '关于应用', '版本 1.0.0', () => {})
            this.SettingRow('🗑', '清除运动数据', '删除所有运动记录', () => { this.clearAllData(); })
          }
          .width('100%')
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, bottom: 24 })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
      .scrollBar(BarState.Off)

      if (this.showWeekDatePicker) {
        Column() {
          Column() {
            DatePicker({
              start: new Date('2020-01-01'),
              end: new Date('2030-12-31'),
              selected: this.currentWeek
            })
              .onChange((value: DatePickerResult) => {
                this.currentWeek = new Date(value.year as number, (value.month as number), value.day as number);
              })

            Row() {
              Button('取消')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.background'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .margin({ right: 12 })
                .onClick(() => { this.showWeekDatePicker = false; })

              Button('确定')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor($r('app.color.primary'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .onClick(() => {
                  this.showWeekDatePicker = false;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          }
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
          .padding({ top: 16 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {})
      }

      if (this.showClearConfirm) {
        Column() {
          Column() {
            Text('确认清除')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ bottom: 12 })
            Text('确定要删除所有运动记录吗？\n此操作不可恢复')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .margin({ bottom: 24 })
            Row({ space: 12 }) {
              Button('取消')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.background'))
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .onClick(() => { this.showClearConfirm = false; })
              Button('确认清除')
                .fontSize(14)
                .fontColor($r('app.color.surface'))
                .backgroundColor('#E53E3E')
                .layoutWeight(1)
                .height(40)
                .borderRadius(20)
                .onClick(() => { this.confirmClearData(); })
            }
            .width('100%')
          }
          .width('80%')
          .padding({ left: 24, right: 24, top: 28, bottom: 28 })
          .backgroundColor($r('app.color.surface'))
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.4)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => { this.showClearConfirm = false; })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  StatItem(label: string, value: string, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
  }

  @Builder
  SettingRow(icon: string, title: string, desc: string, onClick: () => void) {
    Row() {
      Text(icon)
        .fontSize(18)
        .width(24)
        .textAlign(TextAlign.Center)
        .margin({ right: 12 })
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_hint'))
    }
    .width('100%')
    .height(60)
    .padding({ left: 16, right: 16 })
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
    .onClick(onClick)
  }
}

@Component
struct AddRecordDialog {
  selectedDate: string = '';
  onClose: () => void = () => {};
  onConfirm: (record: SportRecord) => void = () => {};

  @State sportType: string = '';
  @State duration: string = '';
  @State calories: string = '';
  @State date: string = '';
  private presetTypes: string[] = ['跑步', '游泳', '户外散步', '室内健身', '骑行', '瑜伽'];

  aboutToAppear() {
    this.date = this.selectedDate;
  }

  build() {
    Column() {
      Column() {
        Text('+ 添加运动记录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 20, bottom: 20 })

        Row() {
          Text('运动类型')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(80)
          TextInput({ placeholder: '输入运动类型', text: this.sportType })
            .layoutWeight(1)
            .height(36)
            .backgroundColor($r('app.color.background'))
            .borderRadius(6)
            .padding({ left: 8 })
            .onChange((value: string) => { this.sportType = value; })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 8 })

        Row({ space: 8 }) {
          ForEach(this.presetTypes, (item: string) => {
            Text(item)
              .fontSize(12)
              .fontColor(this.sportType === item ? $r('app.color.surface') : $r('app.color.primary'))
              .backgroundColor(this.sportType === item ? $r('app.color.primary') : $r('app.color.primary_light'))
              .borderRadius(12)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .onClick(() => { this.sportType = item; })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 16 })

        Row() {
          Text('时长(分钟)')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(80)
          TextInput({ placeholder: '请输入时长' })
            .type(InputType.Number)
            .layoutWeight(1)
            .height(36)
            .backgroundColor($r('app.color.background'))
            .borderRadius(6)
            .padding({ left: 8 })
            .onChange((value: string) => { this.duration = value; })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 16 })

        Row() {
          Text('消耗(千卡)')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(80)
          TextInput({ placeholder: '请输入千卡' })
            .type(InputType.Number)
            .layoutWeight(1)
            .height(36)
            .backgroundColor($r('app.color.background'))
            .borderRadius(6)
            .padding({ left: 8 })
            .onChange((value: string) => { this.calories = value; })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 16 })

        Row() {
          Text('日期')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width(80)
          DatePicker({
            start: new Date('2020-01-01'),
            end: new Date('2030-12-31'),
            selected: new Date(this.date)
          })
            .layoutWeight(1)
            .height(36)
            .backgroundColor($r('app.color.background'))
            .borderRadius(6)
            .onChange((value: DatePickerResult) => {
              const year = value.year as number;
              const month = String((value.month as number) + 1).padStart(2, '0');
              const day = String(value.day as number).padStart(2, '0');
              this.date = `${year}-${month}-${day}`;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ bottom: 24 })

        Row() {
          Button('取消')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.background'))
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .onClick(() => { this.onClose(); })

          Button('添加')
            .fontSize(14)
            .fontColor($r('app.color.surface'))
            .backgroundColor($r('app.color.primary'))
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .margin({ left: 12 })
            .onClick(() => {
              const dur = parseInt(this.duration) || 0;
              const cal = parseInt(this.calories) || 0;
              
              if (!this.sportType || this.sportType.trim().length === 0) {
                AlertDialog.show({
                  title: '提示',
                  message: '请输入运动类型',
                  confirm: {
                    value: '确定',
                    action: () => {}
                  }
                });
                return;
              }
              
              if (!this.duration || dur <= 0) {
                AlertDialog.show({
                  title: '提示',
                  message: '请输入运动时长',
                  confirm: {
                    value: '确定',
                    action: () => {}
                  }
                });
                return;
              }
              
              if (!this.calories || cal <= 0) {
                AlertDialog.show({
                  title: '提示',
                  message: '请输入消耗千卡',
                  confirm: {
                    value: '确定',
                    action: () => {}
                  }
                });
                return;
              }
              
              const record = new SportRecord(
                String(Date.now()),
                this.sportType.trim(),
                dur,
                cal,
                this.date,
                SportDataManager.getInstance().formatDateTime(new Date())
              );
              this.onConfirm(record);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .width('85%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.overlay'))
    .justifyContent(FlexAlign.Center)
    .onClick(() => { this.onClose(); })
  }
}

@Component
struct AIVoiceDialog {
  onClose: () => void = () => {};
  onConfirm: (type: string, duration: number, calories: number) => void = () => {};

  @State isRecording: boolean = false;
  @State hasPermission: boolean = false;
  @State micStarted: boolean = false;
  @State fullVoiceText: string = '';
  @State parsedSport: string = '';
  @State parsedDuration: number = 0;
  @State parsedCalories: number = 0;
  @State errorMessage: string = '';
  private voiceTimeoutId: number = -1;
  private noResultTimeoutId: number = -1;

  aboutToAppear() {
    this.checkAndRequestPermission();
  }

  aboutToDisappear(): void {
    SpeechRecognizerManager.release();
    if (this.voiceTimeoutId > 0) {
      clearTimeout(this.voiceTimeoutId);
      this.voiceTimeoutId = -1;
    }
    if (this.noResultTimeoutId > 0) {
      clearTimeout(this.noResultTimeoutId);
      this.noResultTimeoutId = -1;
    }
  }

  private async checkAndRequestPermission(): Promise<void> {
    const granted = PermissionManager.checkPermission('ohos.permission.MICROPHONE');
    if (granted) {
      this.hasPermission = true;
    } else {
      const result = await PermissionManager.requestPermission('ohos.permission.MICROPHONE');
      this.hasPermission = result;
    }
  }

  private async toggleRecord(): Promise<void> {
    if (this.isRecording) {
      await SpeechRecognizerManager.release();
      this.isRecording = false;
      this.micStarted = false;
      if (this.voiceTimeoutId > 0) {
        clearTimeout(this.voiceTimeoutId);
        this.voiceTimeoutId = -1;
      }
      if (this.noResultTimeoutId > 0) {
        clearTimeout(this.noResultTimeoutId);
        this.noResultTimeoutId = -1;
      }
    } else {
      this.fullVoiceText = '';
      this.parsedSport = '';
      this.parsedDuration = 0;
      this.parsedCalories = 0;
      this.errorMessage = '';
      this.micStarted = false;
      this.isRecording = true;
      await SpeechRecognizerManager.init((text: string, isFinal: boolean, isLast: boolean) => {
        this.fullVoiceText = text;
        if (isFinal || isLast) {
          const result = SportVoiceParser.parse(text);
          if (result.sportName.length > 0) {
            this.parsedSport = result.sportName;
            this.parsedDuration = result.duration;
            this.parsedCalories = result.calories;
          }
        }
        if (isLast) {
          SpeechRecognizerManager.isListening = false;
        }
      }, (errorCode: number, errorMessage: string) => {
        this.errorMessage = errorMessage;
        this.isRecording = false;
        this.micStarted = false;
        console.error('语音识别错误回调:', errorCode, errorMessage);
      }, () => {
        // 麦克风已激活
        this.micStarted = true;
        // 启动无结果超时检测：10秒内无任何识别结果则提示
        this.noResultTimeoutId = setTimeout(() => {
          if (this.isRecording && this.fullVoiceText.length === 0) {
            this.errorMessage = '未检测到语音输入，请检查麦克风是否正常或网络是否畅通';
          }
        }, 10000);
      });
      this.voiceTimeoutId = setTimeout(() => {
        if (this.isRecording) {
          SpeechRecognizerManager.release();
          this.isRecording = false;
          this.micStarted = false;
        }
      }, 60000);
    }
  }

  private confirmAdd(): void {
    SpeechRecognizerManager.release();
    if (this.voiceTimeoutId > 0) {
      clearTimeout(this.voiceTimeoutId);
      this.voiceTimeoutId = -1;
    }
    if (this.noResultTimeoutId > 0) {
      clearTimeout(this.noResultTimeoutId);
      this.noResultTimeoutId = -1;
    }
    this.isRecording = false;
    this.micStarted = false;
    if (this.parsedSport.length > 0) {
      this.onConfirm(this.parsedSport, this.parsedDuration, this.parsedCalories);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        // 标题
        Text('🎤 AI语音记录运动')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 24 })

        // 权限状态
        Text(this.hasPermission ? '✅ 麦克风权限就绪' : '⚠ 需要麦克风权限')
          .fontSize(12)
          .fontColor(this.hasPermission ? '#36C960' : '#F5A623')

        // 错误信息
        if (this.errorMessage.length > 0) {
          Row({ space: 4 }) {
            Text('⚠️')
              .fontSize(12)
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor('#E74C3C')
          }
          .width('100%')
          .padding({ top: 8, bottom: 4, left: 12, right: 12 })
          .backgroundColor('#FFF0F0')
          .borderRadius(8)
          .margin({ top: 4, bottom: 4 })
        }

        // 麦克风图标
        Column() {
          Text(this.isRecording ? '🔴' : '🎙')
            .fontSize(64)
        }
        .width(130)
        .height(130)
        .borderRadius(65)
        .backgroundColor(this.isRecording ? '#FFF0F0' : $r('app.color.background'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        // 状态文字
        Text(this.isRecording ? (this.micStarted ? '正在收音，请说话...' : '正在启动麦克风...') : '点击下方按钮开始录音')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        // 开始/结束录音按钮
        Button(this.isRecording ? '⏹ 结束录音' : '🎙 开始录音')
          .fontSize(15)
          .fontColor($r('app.color.surface'))
          .fontWeight(FontWeight.Medium)
          .width('80%')
          .height(46)
          .borderRadius(23)
          .enabled(this.hasPermission)
          .linearGradient({
            angle: 90,
            colors: [[$r('app.color.gradient_start'), 0], [$r('app.color.gradient_end'), 1]]
          })
          .opacity(this.hasPermission ? 1 : 0.4)
          .onClick(() => { this.toggleRecord(); })

        // 识别原文
        if (this.fullVoiceText.length > 0) {
          Column() {
            Text('识别原文：')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(this.fullVoiceText)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .padding(8)
              .backgroundColor($r('app.color.background'))
              .borderRadius(8)
          }
          .width('100%')
        }

        // 解析结果色块
        if (this.parsedSport.length > 0) {
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
        }

        // 确认添加按钮
        Button('确认添加')
          .fontSize(15)
          .fontColor($r('app.color.surface'))
          .fontWeight(FontWeight.Medium)
          .width('80%')
          .height(44)
          .borderRadius(22)
          .enabled(this.parsedSport.length > 0)
          .backgroundColor(this.parsedSport.length > 0 ? '#36C960' : $r('app.color.divider'))
          .onClick(() => { this.confirmAdd(); })

        // 提示文字
        Text('💡 尝试说 "我刚跑步 20 分钟，消耗 150 千卡"')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 20 })
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
    .alignContent(Alignment.Center)
    .onClick(() => {
      SpeechRecognizerManager.release();
      this.onClose();
    })
  }
}

