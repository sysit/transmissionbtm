// transmissionbtm — Keep-Alive Manager
//
// Holds a HarmonyOS CONTINUOUS TASK (long-running background task) so the OS
// does not freeze this process while a transfer is active. A frozen process
// cannot run libtransmission's event thread, so background downloads would
// stall until the app was brought back to the foreground (foregrounding thaws
// the process immediately).
//
// Why a continuous task and not @ohos.runningLock: on HarmonyOS a backgrounded
// app is frozen by default; the documented exemption is a continuous task
// (ohos.permission.KEEP_BACKGROUND_RUNNING + module.json5 backgroundModes +
// backgroundTaskManager.startBackgroundRunning). runningLock would additionally
// need ohos.permission.RUNNING_LOCK and is not the supported keep-alive path.
//
// Lifecycle:
//   acquire(reason) → startBackgroundRunning(context, ['dataTransfer'], wantAgent)
//   release()       → stopBackgroundRunning(context)
//   isHolding()     → check current state
//
// The system publishes the mandatory "running in background" notification when
// the task starts and removes it when the task stops.

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'KeepAliveManager';
/** Must match module.json5 → abilities[EntryAbility].backgroundModes. */
const BACKGROUND_MODES: string[] = ['dataTransfer'];

export class KeepAliveManager {
  /** Resolved lazily: the UIAbilityContext is only valid once the page is up. */
  private contextProvider: () => common.UIAbilityContext;
  private active: boolean = false;

  constructor(contextProvider: () => common.UIAbilityContext) {
    this.contextProvider = contextProvider;
  }

  /**
   * Start the continuous task that keeps this process alive in the background.
   *
   * @param reason Human-readable reason for the task (logged).
   */
  async acquire(reason: string): Promise<void> {
    if (this.active) {
      return;
    }
    try {
      const context = this.contextProvider();
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(context, BACKGROUND_MODES, agent);
      this.active = true;
      hilog.info(0x0001, TAG, 'Continuous task started: %{public}s', reason);
    } catch (err) {
      hilog.error(0x0001, TAG, 'Failed to start continuous task: %{private}s', String(err));
    }
  }

  /**
   * Stop the continuous task, allowing the system to freeze the process again.
   * Safe to call when no task is running (no-op).
   */
  release(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    try {
      const context = this.contextProvider();
      backgroundTaskManager.stopBackgroundRunning(context).catch((e: Error) => {
        hilog.error(0x0001, TAG, 'Failed to stop continuous task: %{private}s', String(e));
      });
      hilog.info(0x0001, TAG, 'Continuous task stopped');
    } catch (err) {
      hilog.error(0x0001, TAG, 'Failed to stop continuous task: %{private}s', String(err));
    }
  }

  /** True while the continuous task is held. */
  isHolding(): boolean {
    return this.active;
  }
}
