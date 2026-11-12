import { speechRecognizer } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SpeechRecognizerMgr';
const DOMAIN = 0x0001;

// 引擎状态枚举（对应底层 AudioCapturer/SpeechCapturer 状态码）
enum EngineState {
  IDLE = 0,       // 未初始化
  PREPARED = 1,   // 引擎已创建，待启动
  RUNNING = 2,    // 正在录音识别
  STOPPING = 3,   // 正在停止中
  RELEASED = 4,   // 已释放（对应 Illegal state:4 的 RELEASED 状态）
  ERROR = -1      // 异常状态（对应 Illegal state:4294967295 = unsigned -1）
}

class SpeechRecognizerManager {
  // ========== 引擎实例 ==========
  private static asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private static sessionId: string = '';

  // ========== 回调（UI 层注入） ==========
  private static resultCallback: ((text: string, isFinal: boolean, isLast: boolean) => void) | null = null;
  private static errorCallback: ((errorCode: number, errorMessage: string) => void) | null = null;
  private static startCallback: (() => void) | null = null;

  // ========== 监听器（静态成员持久化，杜绝 cb == nullptr） ==========
  private static recognitionListener: speechRecognizer.RecognitionListener | null = null;

  // ========== 运行时状态 ==========
  static isListening: boolean = false;
  private static fullText: string = '';
  private static pendingText: string = '';
  private static engineInstanceId: number = 0;

  // ========== 状态机 ==========
  private static engineState: EngineState = EngineState.IDLE;

  // ========== 互斥锁（防多线程读写竞争：主线程启停 vs 音频读线程回调） ==========
  private static mutexChain: Promise<void> = Promise.resolve();

  // ========== 销毁流程标记 ==========
  private static isShuttingDown: boolean = false;

  // ========== 超时常量 ==========
  private static readonly SHUTDOWN_TIMEOUT_MS = 3000;
  private static readonly STATE_WAIT_RETRIES = 30;
  private static readonly STATE_WAIT_INTERVAL_MS = 100;

  // ========== 状态码可读映射 ==========
  private static stateName(s: EngineState): string {
    switch (s) {
      case EngineState.IDLE: return 'IDLE(0)';
      case EngineState.PREPARED: return 'PREPARED(1)';
      case EngineState.RUNNING: return 'RUNNING(2)';
      case EngineState.STOPPING: return 'STOPPING(3)';
      case EngineState.RELEASED: return 'RELEASED(4)';
      case EngineState.ERROR: return 'ERROR(-1)';
      default: return `UNKNOWN(${s})`;
    }
  }

  // ========== 安全设置状态（带变更通知） ==========
  private static setEngineState(newState: EngineState): void {
    const oldState = SpeechRecognizerManager.engineState;
    if (oldState !== newState) {
      SpeechRecognizerManager.engineState = newState;
      SpeechRecognizerManager.onEngineStateChange(newState, oldState);
    }
  }

  // ========== 状态前置校验工具 ==========
  private static checkStateBeforeStart(): boolean {
    const state = SpeechRecognizerManager.engineState;
    hilog.info(DOMAIN, TAG, 'checkStateBeforeStart: 当前状态=%{public}s', 
      SpeechRecognizerManager.stateName(state));
    
    if (state === EngineState.RELEASED) {
      hilog.warn(DOMAIN, TAG, 'checkStateBeforeStart: 引擎已释放(RELEASED)，需要重新初始化');
      return false;
    }
    
    if (state === EngineState.ERROR) {
      hilog.warn(DOMAIN, TAG, 'checkStateBeforeStart: 引擎错误(ERROR)，需要重置');
      return false;
    }
    
    if (state === EngineState.RUNNING || state === EngineState.STOPPING) {
      hilog.warn(DOMAIN, TAG, 'checkStateBeforeStart: 引擎正在运行或停止中，状态=%{public}s', 
        SpeechRecognizerManager.stateName(state));
      return false;
    }
    
    return true;
  }

  private static checkStateBeforeStop(): boolean {
    const state = SpeechRecognizerManager.engineState;
    hilog.info(DOMAIN, TAG, 'checkStateBeforeStop: 当前状态=%{public}s', 
      SpeechRecognizerManager.stateName(state));
    
    if (state === EngineState.RELEASED) {
      hilog.info(DOMAIN, TAG, 'checkStateBeforeStop: 引擎已释放(RELEASED)，无需停止');
      return false;
    }
    
    if (state === EngineState.IDLE) {
      hilog.info(DOMAIN, TAG, 'checkStateBeforeStop: 引擎未启动(IDLE)，无需停止');
      return false;
    }
    
    if (state === EngineState.STOPPING) {
      hilog.warn(DOMAIN, TAG, 'checkStateBeforeStop: 引擎正在停止中(STOPPING)，跳过重复停止');
      return false;
    }
    
    if (state !== EngineState.RUNNING && state !== EngineState.PREPARED && state !== EngineState.ERROR) {
      hilog.warn(DOMAIN, TAG, 'checkStateBeforeStop: 无效状态=%{public}s，跳过停止', 
        SpeechRecognizerManager.stateName(state));
      return false;
    }
    
    return true;
  }

  // ========== 异步安全停止函数（模块1核心） ==========
  private static async asyncSafeStopCapturer(): Promise<void> {
    return SpeechRecognizerManager.acquireMutex<void>(async () => {
      hilog.info(DOMAIN, TAG, 'asyncSafeStopCapturer: 开始, sessionId=%{public}s, instanceId=%{public}d, 当前状态=%{public}s', 
        SpeechRecognizerManager.sessionId || 'N/A',
        SpeechRecognizerManager.engineInstanceId,
        SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState));
      
      // 状态前置校验
      if (!SpeechRecognizerManager.checkStateBeforeStop()) {
        hilog.info(DOMAIN, TAG, 'asyncSafeStopCapturer: 状态校验失败，跳过停止操作');
        return;
      }
      
      if (SpeechRecognizerManager.isShuttingDown) {
        hilog.info(DOMAIN, TAG, 'asyncSafeStopCapturer: 已有销毁流程在执行中，跳过');
        return;
      }

      // 业务流程验证
      if (!SpeechRecognizerManager.beforeCriticalOperation('stop')) {
        hilog.error(DOMAIN, TAG, 'asyncSafeStopCapturer: 业务流程验证失败，跳过停止操作');
        return;
      }
      
      SpeechRecognizerManager.isShuttingDown = true;
      SpeechRecognizerManager.setEngineState(EngineState.STOPPING);
      
      const engineToShutdown = SpeechRecognizerManager.asrEngine;
      const sessionToCancel = SpeechRecognizerManager.sessionId;
      
      // 立即置空，防止回调触发
      SpeechRecognizerManager.asrEngine = null;
      SpeechRecognizerManager.recognitionListener = null;
      
      if (engineToShutdown) {
        try {
          await SpeechRecognizerManager.safeStopEngine(engineToShutdown, sessionToCancel);
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'asyncSafeStopCapturer: 停止引擎失败: %{public}s', 
            JSON.stringify(e));
        }
      }
      
      // 无论成功失败，强制执行降级清理
      SpeechRecognizerManager.forceCleanup();
      SpeechRecognizerManager.isShuttingDown = false;
      
      hilog.info(DOMAIN, TAG, 'asyncSafeStopCapturer: 完成, 最终状态=%{public}s, instanceId=%{public}d',
        SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState),
        SpeechRecognizerManager.engineInstanceId);
    });
  }

  // ========== 互斥锁获取 ==========
  private static async acquireMutex<T>(fn: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      SpeechRecognizerManager.mutexChain = SpeechRecognizerManager.mutexChain.then(async () => {
        try {
          const result = await fn();
          resolve(result);
        } catch (e) {
          reject(e);
        }
      });
    });
  }

  // ========== 增强型互斥锁获取（带超时和状态检查） ==========
  private static async acquireMutexWithTimeout<T>(
    fn: () => Promise<T>,
    timeoutMs: number = 5000,
    operationName: string = 'unknown'
  ): Promise<T> {
    return new Promise<T>(async (resolve, reject) => {
      const startTime = Date.now();
      let mutexAcquired = false;
      
      // 尝试获取mutex，带超时
      const timeoutPromise = new Promise<never>((_, timeoutReject) => {
        setTimeout(() => {
          if (!mutexAcquired) {
            timeoutReject(new Error(`acquireMutexWithTimeout: ${operationName} 操作超时 (${timeoutMs}ms)`));
          }
        }, timeoutMs);
      });

      try {
        // 等待mutex或超时
        await Promise.race([
          (async () => {
            SpeechRecognizerManager.mutexChain = SpeechRecognizerManager.mutexChain.then(async () => {
              mutexAcquired = true;
              const acquireTime = Date.now() - startTime;
              if (acquireTime > 100) {
                hilog.warn(DOMAIN, TAG, 'acquireMutexWithTimeout: %{public}s 等待mutex %{public}dms', 
                  operationName, acquireTime);
              }
              
              try {
                const result = await fn();
                resolve(result);
              } catch (e) {
                reject(e);
              }
            });
          })(),
          timeoutPromise
        ]);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'acquireMutexWithTimeout: %{public}s 失败: %{public}s', 
          operationName, JSON.stringify(error));
        reject(error);
      }
    });
  }

  // ========== 超时工具 ==========
  private static timeoutPromise(ms: number): Promise<never> {
    return new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error(`操作超时 ${ms}ms`)), ms);
    });
  }

  // ========== 降级清理（不调用任何框架 API，仅重置应用层状态） ==========
  private static forceCleanup(): void {
    // 记录清理前的状态信息
    const prevState = SpeechRecognizerManager.engineState;
    const instanceId = SpeechRecognizerManager.engineInstanceId;
    const sessionId = SpeechRecognizerManager.sessionId || 'N/A';
    
    hilog.info(DOMAIN, TAG, 'forceCleanup: 开始清理, 当前状态=%{public}s, instanceId=%{public}d, sessionId=%{public}s',
      SpeechRecognizerManager.stateName(prevState), instanceId, sessionId);
    
    // 关键顺序：先置空引擎，再清监听器，杜绝 cb == nullptr
    SpeechRecognizerManager.asrEngine = null;
    SpeechRecognizerManager.recognitionListener = null;
    SpeechRecognizerManager.isListening = false;
    SpeechRecognizerManager.setEngineState(EngineState.RELEASED);
    SpeechRecognizerManager.resultCallback = null;
    SpeechRecognizerManager.errorCallback = null;
    SpeechRecognizerManager.startCallback = null;
    SpeechRecognizerManager.fullText = '';
    SpeechRecognizerManager.pendingText = '';
    
    hilog.info(DOMAIN, TAG, 'forceCleanup: 完成清理, 状态→%{public}s, instanceId=%{public}d, sessionId=%{public}s',
      SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState), instanceId, sessionId);
  }

  // ========== 模块1.2：安全停止引擎（含超时保护 + 状态校验） ==========
  private static async safeStopEngine(
    engine: speechRecognizer.SpeechRecognitionEngine,
    session: string
  ): Promise<void> {
    hilog.info(DOMAIN, TAG, 'safeStopEngine: 开始, 当前状态=%{public}s, session=%{public}s, instanceId=%{public}d',
      SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState),
      session || 'N/A',
      SpeechRecognizerManager.engineInstanceId);

    try {
      await Promise.race<void>([
        new Promise<void>((resolve, reject) => {
          setTimeout(async () => {
            try {
              // 固定销毁顺序（不可调换）：cancel → shutdown
              engine.cancel(session);
              engine.shutdown();
              resolve();
            } catch (e) {
              // 检查是否为"Illegal state"错误，如果是则忽略，因为引擎可能已经释放
              const errorStr = JSON.stringify(e);
              if (errorStr.includes('Illegal state') || errorStr.includes('state:4')) {
                hilog.info(DOMAIN, TAG, 'safeStopEngine: 引擎已处于释放状态，跳过停止操作');
                resolve(); // 不视为错误，正常继续
              } else {
                reject(e);
              }
            }
          }, 0);
        }),
        SpeechRecognizerManager.timeoutPromise(SpeechRecognizerManager.SHUTDOWN_TIMEOUT_MS)
      ]);
      hilog.info(DOMAIN, TAG, 'safeStopEngine: cancel+shutdown 完成');
    } catch (e) {
      const errorStr = JSON.stringify(e);
      // 如果是"Illegal state"错误，只记录信息，不视为异常
      if (errorStr.includes('Illegal state') || errorStr.includes('state:4')) {
        hilog.info(DOMAIN, TAG, 'safeStopEngine: 引擎已处于释放状态，无需停止');
      } else {
        hilog.warn(DOMAIN, TAG, 'safeStopEngine: 超时/异常(3s), 跳过框架API, 执行降级清理: %{public}s',
          errorStr);
      }
    }
  }

  // ========== 统一安全销毁（含 Mutex 保护） ==========
  static async safeShutdown(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'safeShutdown: 调用统一安全销毁接口');
    await SpeechRecognizerManager.asyncSafeStopCapturer();
  }

  // ========== 模块1.3：安全启动（状态前置校验 + Mutex） ==========
  static async init(callback: (text: string, isFinal: boolean, isLast: boolean) => void,
    errorCb?: (errorCode: number, errorMessage: string) => void,
    startCb?: () => void): Promise<void> {

    return SpeechRecognizerManager.acquireMutex<void>(async () => {
      hilog.info(DOMAIN, TAG, 'init: 开始, 当前状态=%{public}s',
        SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState));
      
      // 状态前置校验
      if (!SpeechRecognizerManager.checkStateBeforeStart()) {
        hilog.warn(DOMAIN, TAG, 'init: 状态校验失败，拒绝启动');
        if (errorCb) {
          errorCb(-1, '语音引擎状态异常，请稍后再试');
        }
        return;
      }

      // 业务流程验证
      if (!SpeechRecognizerManager.beforeCriticalOperation('init')) {
        hilog.error(DOMAIN, TAG, 'init: 业务流程验证失败，拒绝启动');
        if (errorCb) {
          errorCb(-2, '语音引擎业务流程异常，请稍后再试');
        }
        return;
      }

      // 销毁旧实例（如果存在）
      if (SpeechRecognizerManager.engineState !== EngineState.IDLE) {
        hilog.info(DOMAIN, TAG, 'init: 先销毁旧引擎, 当前状态=%{public}s',
          SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState));
        // 使用异步安全停止函数
        await SpeechRecognizerManager.asyncSafeStopCapturer();
      }

      // 准备新实例
      SpeechRecognizerManager.engineInstanceId++;
      SpeechRecognizerManager.sessionId = 'asr_' + Date.now();
      SpeechRecognizerManager.resultCallback = callback;
      SpeechRecognizerManager.errorCallback = errorCb || null;
      SpeechRecognizerManager.startCallback = startCb || null;
      SpeechRecognizerManager.fullText = '';
      SpeechRecognizerManager.pendingText = '';
      SpeechRecognizerManager.setEngineState(EngineState.PREPARED);

      const currentInstanceId = SpeechRecognizerManager.engineInstanceId;
      hilog.info(DOMAIN, TAG, 'init: sessionId=%{public}s, instanceId=%{public}d, 状态→PREPARED',
        SpeechRecognizerManager.sessionId, currentInstanceId);

      try {
        // 异步子线程创建引擎
        await new Promise<void>((resolve, reject) => {
          setTimeout(async () => {
            try {
              const extraParam: Record<string, Object> = {
                'locate': 'CN',
                'recognizerMode': 'long'
              };
              const initParamsInfo: speechRecognizer.CreateEngineParams = {
                language: 'zh-CN',
                online: 1,
                extraParams: extraParam
              };
              SpeechRecognizerManager.asrEngine = await speechRecognizer.createEngine(initParamsInfo);
              SpeechRecognizerManager.setEngineState(EngineState.PREPARED);
              hilog.info(DOMAIN, TAG, 'createEngine 成功, 状态→PREPARED, instanceId=%{public}d, sessionId=%{public}s',
                SpeechRecognizerManager.engineInstanceId, SpeechRecognizerManager.sessionId || 'N/A');

              // 监听器全字段显式赋值，杜绝未初始化野指针
              SpeechRecognizerManager.recognitionListener = {
                onStart: (_sessionId: string, _eventMessage: string) => {
                  SpeechRecognizerManager.isListening = true;
                  SpeechRecognizerManager.setEngineState(EngineState.RUNNING);
                  hilog.info(DOMAIN, TAG, 'onStart: 麦克风激活, 状态→RUNNING, sid=%{public}s, instanceId=%{public}d',
                    _sessionId, currentInstanceId);
                  if (SpeechRecognizerManager.startCallback) {
                    SpeechRecognizerManager.startCallback();
                  }
                },
                onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
                  const text = result.result;
                  const isFinal = result.isFinal;
                  const isLast = result.isLast;
                  if (isFinal) {
                    SpeechRecognizerManager.fullText += text;
                    SpeechRecognizerManager.pendingText = '';
                  } else {
                    SpeechRecognizerManager.pendingText = text;
                  }
                  const displayText = SpeechRecognizerManager.fullText + SpeechRecognizerManager.pendingText;
                  if (SpeechRecognizerManager.resultCallback) {
                    SpeechRecognizerManager.resultCallback(displayText, isFinal, isLast);
                  }
                  if (isLast) {
                    hilog.info(DOMAIN, TAG, 'onResult: 完全结束');
                  }
                },
                onError: (_sessionId: string, errorCode: number, errorMessage: string) => {
                  SpeechRecognizerManager.isListening = false;
                  hilog.error(DOMAIN, TAG, 'onError: code=%{public}d, msg=%{public}s, sid=%{public}s, instanceId=%{public}d',
                    errorCode, errorMessage, _sessionId, currentInstanceId);
                  if (SpeechRecognizerManager.errorCallback) {
                    SpeechRecognizerManager.errorCallback(errorCode, errorMessage);
                  }
                  // 仅本代引擎回调执行销毁，防止旧回调误关新引擎
                  if (SpeechRecognizerManager.engineInstanceId === currentInstanceId) {
                    SpeechRecognizerManager.safeShutdown();
                  }
                },
                onComplete: (_sessionId: string, _eventMessage: string) => {
                  SpeechRecognizerManager.isListening = false;
                  hilog.info(DOMAIN, TAG, 'onComplete: 识别正常结束, sid=%{public}s, instanceId=%{public}d',
                    _sessionId, currentInstanceId);
                  if (SpeechRecognizerManager.engineInstanceId === currentInstanceId) {
                    SpeechRecognizerManager.safeShutdown();
                  }
                },
                onEvent: (_sessionId: string, _eventCode: number, _eventMessage: string) => {
                  hilog.info(DOMAIN, TAG, 'onEvent: code=%{public}d, msg=%{public}s, sid=%{public}s, instanceId=%{public}d',
                    _eventCode, _eventMessage, _sessionId, currentInstanceId);
                  
                  // 处理不同的事件代码
                  switch (_eventCode) {
                    case 3:
                      hilog.info(DOMAIN, TAG, 'ASR连接云服务中...');
                      break;
                    case 1000: // 假设OnAbilityDisconnectDone的事件代码是1000，需要根据实际SDK调整
                    case 1001:
                      hilog.warn(DOMAIN, TAG, 'onEvent: ASR能力断开连接，事件代码=%{public}d', _eventCode);
                      // 异步处理能力断开，避免阻塞事件回调
                      setTimeout(() => {
                        SpeechRecognizerManager.handleAbilityDisconnect().catch((err: Error) => {
                          hilog.error(DOMAIN, TAG, 'handleAbilityDisconnect失败: %{public}s', JSON.stringify(err));
                        });
                      }, 0);
                      break;
                    default:
                      hilog.debug(DOMAIN, TAG, 'onEvent: 未知事件代码 %{public}d', _eventCode);
                      break;
                  }
                }
              };

              SpeechRecognizerManager.asrEngine.setListener(SpeechRecognizerManager.recognitionListener);

              const audioInfo: speechRecognizer.AudioInfo = {
                audioType: 'pcm',
                sampleRate: 16000,
                soundChannel: 1,
                sampleBit: 16
              };
              SpeechRecognizerManager.asrEngine.startListening({
                sessionId: SpeechRecognizerManager.sessionId,
                audioInfo: audioInfo,
                extraParams: {
                  'recognitionMode': 0,
                  'maxAudioDuration': 60000
                }
              });
              SpeechRecognizerManager.setEngineState(EngineState.RUNNING);
              hilog.info(DOMAIN, TAG, 'init 完成: startListening 成功, 状态→RUNNING, instanceId=%{public}d, sessionId=%{public}s',
                SpeechRecognizerManager.engineInstanceId, SpeechRecognizerManager.sessionId || 'N/A');
              resolve();
            } catch (err) {
              reject(err);
            }
          }, 0);
        });
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'init 异常: %{public}s', JSON.stringify(err));
        SpeechRecognizerManager.setEngineState(EngineState.ERROR);
        SpeechRecognizerManager.asrEngine = null;
        SpeechRecognizerManager.recognitionListener = null;
        if (SpeechRecognizerManager.errorCallback) {
          SpeechRecognizerManager.errorCallback(-2, '语音引擎初始化失败，请检查网络连接后重试');
        }
      }
    });
  }

  // ========== 模块2.1+2.2：内部关闭（在 Mutex 内调用） ==========
  private static async internalShutdown(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'internalShutdown: 调用内部关闭接口');
    await SpeechRecognizerManager.asyncSafeStopCapturer();
  }

  // ========== 模块4：全局释放入口 ==========
  static async release(): Promise<void> {
    await SpeechRecognizerManager.acquireMutex<void>(async () => {
      // 业务流程验证
      if (!SpeechRecognizerManager.beforeCriticalOperation('release')) {
        hilog.error(DOMAIN, TAG, 'release: 业务流程验证失败，跳过释放操作');
        return;
      }
      
      const prevState = SpeechRecognizerManager.engineState;
      await SpeechRecognizerManager.internalShutdown();
      hilog.info(DOMAIN, TAG, 'release 完成: %{public}s → RELEASED',
        SpeechRecognizerManager.stateName(prevState));
    });
  }

  // ========== 模块2.1：OnAbilityDisconnectDone 处理 ==========
  private static async handleAbilityDisconnect(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'handleAbilityDisconnect: ASR能力断开连接，执行清理流程');
    
    // 记录当前状态
    const currentState = SpeechRecognizerManager.engineState;
    hilog.info(DOMAIN, TAG, 'handleAbilityDisconnect: 断开前状态=%{public}s', 
      SpeechRecognizerManager.stateName(currentState));
    
    // 立即停止音频采集和ASR引擎
    await SpeechRecognizerManager.asyncSafeStopCapturer();
    
    // 执行远端对象清理
    SpeechRecognizerManager.forceCleanup();
    
    // 重置所有状态
    SpeechRecognizerManager.engineInstanceId = 0;
    SpeechRecognizerManager.sessionId = '';
    
    hilog.info(DOMAIN, TAG, 'handleAbilityDisconnect: 清理完成，状态=%{public}s', 
      SpeechRecognizerManager.stateName(SpeechRecognizerManager.engineState));
  }

  // ========== 模块2.2：适配forceCleanup状态变更监听 ==========
  private static onEngineStateChange(newState: EngineState, oldState: EngineState): void {
    hilog.info(DOMAIN, TAG, 'onEngineStateChange: %{public}s → %{public}s', 
      SpeechRecognizerManager.stateName(oldState), 
      SpeechRecognizerManager.stateName(newState));
    
    // 当状态变为RELEASED时，确保所有资源已清理
    if (newState === EngineState.RELEASED) {
      hilog.info(DOMAIN, TAG, 'onEngineStateChange: 引擎已释放，确保资源清理完成');
      // 可以在这里触发额外的清理逻辑
    }
  }

  // ========== 模块4：标准业务流程强制规范 ==========
  
  /**
   * 标准业务流程：正常识别结束流程
   * 1. 用户停止录音
   * 2. 调用release()方法
   * 3. 执行asyncSafeStopCapturer()
   * 4. 状态变为RELEASED
   * 5. 清理所有资源
   */
  private static enforceNormalFlow(): void {
    hilog.info(DOMAIN, TAG, 'enforceNormalFlow: 执行标准正常流程验证');
    
    // 验证当前状态是否符合正常流程
    const currentState = SpeechRecognizerManager.engineState;
    if (currentState === EngineState.RUNNING || currentState === EngineState.STOPPING) {
      hilog.info(DOMAIN, TAG, 'enforceNormalFlow: 当前状态=%{public}s，符合正常流程', 
        SpeechRecognizerManager.stateName(currentState));
    } else if (currentState === EngineState.RELEASED) {
      hilog.info(DOMAIN, TAG, 'enforceNormalFlow: 引擎已释放，无需执行正常流程');
    } else {
      hilog.warn(DOMAIN, TAG, 'enforceNormalFlow: 异常状态=%{public}s，可能未按标准流程执行', 
        SpeechRecognizerManager.stateName(currentState));
    }
  }

  /**
   * 标准业务流程：异常兜底流程
   * 1. 检测到异常（错误、超时、能力断开等）
   * 2. 立即执行forceCleanup()
   * 3. 重置所有状态
   * 4. 记录异常信息
   */
  private static enforceExceptionFlow(errorType: string, errorDetails: string): void {
    hilog.warn(DOMAIN, TAG, 'enforceExceptionFlow: 异常类型=%{public}s, 详情=%{public}s', 
      errorType, errorDetails);
    
    // 记录异常发生时的状态
    const currentState = SpeechRecognizerManager.engineState;
    const instanceId = SpeechRecognizerManager.engineInstanceId;
    const sessionId = SpeechRecognizerManager.sessionId || 'N/A';
    
    hilog.error(DOMAIN, TAG, 'enforceExceptionFlow: 异常发生时状态=%{public}s, instanceId=%{public}d, sessionId=%{public}s',
      SpeechRecognizerManager.stateName(currentState), instanceId, sessionId);
    
    // 强制执行异常兜底流程
    SpeechRecognizerManager.forceCleanup();
    
    // 重置状态
    SpeechRecognizerManager.engineInstanceId = 0;
    SpeechRecognizerManager.sessionId = '';
    SpeechRecognizerManager.isShuttingDown = false;
    
    hilog.info(DOMAIN, TAG, 'enforceExceptionFlow: 异常兜底流程执行完成');
  }

  /**
   * 业务流程验证器：在关键节点调用，确保符合标准流程
   */
  private static validateBusinessFlow(operation: string): boolean {
    const currentState = SpeechRecognizerManager.engineState;
    const isValid = SpeechRecognizerManager.checkStateTransition(operation, currentState);
    
    if (!isValid) {
      hilog.error(DOMAIN, TAG, 'validateBusinessFlow: 操作"%{public}s"在状态%{public}s下无效',
        operation, SpeechRecognizerManager.stateName(currentState));
      
      // 触发异常兜底流程
      SpeechRecognizerManager.enforceExceptionFlow('INVALID_STATE_TRANSITION', 
        `操作${operation}在状态${SpeechRecognizerManager.stateName(currentState)}下无效`);
    }
    
    return isValid;
  }

  /**
   * 状态转移检查器
   */
  private static checkStateTransition(operation: string, currentState: EngineState): boolean {
    // 定义允许的状态转移规则
    const validTransitions: Record<string, EngineState[]> = {
      'init': [EngineState.IDLE, EngineState.RELEASED, EngineState.ERROR],
      'start': [EngineState.PREPARED],
      'stop': [EngineState.RUNNING, EngineState.PREPARED, EngineState.ERROR],
      'release': [EngineState.IDLE, EngineState.PREPARED, EngineState.RUNNING, EngineState.STOPPING, EngineState.ERROR],
      'forceCleanup': [EngineState.IDLE, EngineState.PREPARED, EngineState.RUNNING, EngineState.STOPPING, EngineState.ERROR, EngineState.RELEASED]
    };

    const allowedStates = validTransitions[operation] || [];
    const isAllowed = allowedStates.includes(currentState);
    
    if (!isAllowed) {
      hilog.warn(DOMAIN, TAG, 'checkStateTransition: 操作"%{public}s"不允许从状态%{public}s开始',
        operation, SpeechRecognizerManager.stateName(currentState));
    }
    
    return isAllowed;
  }

  /**
   * 在关键操作前验证业务流程
   */
  private static beforeCriticalOperation(operation: string): boolean {
    if (!SpeechRecognizerManager.validateBusinessFlow(operation)) {
      hilog.error(DOMAIN, TAG, 'beforeCriticalOperation: 操作"%{public}s"被拒绝，状态验证失败', operation);
      return false;
    }
    
    hilog.debug(DOMAIN, TAG, 'beforeCriticalOperation: 操作"%{public}s"状态验证通过', operation);
    return true;
  }
}

export default SpeechRecognizerManager;
