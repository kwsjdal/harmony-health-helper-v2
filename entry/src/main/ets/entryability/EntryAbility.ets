import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SportDataManager } from '../data/SportDataManager';
import SpeechRecognizerManager from '../utils/SpeechRecognizerManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    AppStorage.setOrCreate('appBundleName', this.context.applicationInfo.name);
    SportDataManager.getInstance().init(this.context);
    this.handleNotificationWant(want);
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, 'testTag', 'Ability onNewWant');
    this.handleNotificationWant(want);
  }

  handleNotificationWant(want: Want): void {
    if (want.parameters && want.parameters['targetTab'] === '1') {
      AppStorage.setOrCreate('navigateTab', 1);
    }
  }

  onDestroy(): void {
    SpeechRecognizerManager.release();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    SpeechRecognizerManager.release();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // 切后台时释放 ASR 资源，防止 ASR Ability 断开后残留占用
    SpeechRecognizerManager.release();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}