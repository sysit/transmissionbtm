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
  /** Process-global listeners are registered at most once. */
  private listenersRegistered: boolean = false;
  /** Uptime ms of the last system-forced cancel (backoff guard, see below). */
  private lastSystemCancelAt: number = 0;

  constructor(contextProvider: () => common.UIAbilityContext) {
    this.contextProvider = contextProvider;
  }

  /**
   * Log the system's view of our continuous task. Without these the OS can
   * suspend or cancel the task (low-speed check, user swipe, system policy) and
   * the app has no record of it — the only visible symptom is "background
   * downloads stopped", which is indistinguishable from the OS freezing the
   * process for lack of any keep-alive at all.
   */
  private registerStateListeners(): void {
    if (this.listenersRegistered) {
      return;
    }
    this.listenersRegistered = true;
    try {
      backgroundTaskManager.on('continuousTaskCancel',
        (info: backgroundTaskManager.ContinuousTaskCancelInfo) => {
          hilog.warn(0x0001, TAG,
            'Continuous task CANCELLED id=%{public}d reason=%{public}d', info.id, info.reason);
          // A user-initiated cancel (swiped the notification away) means the
          // user wants background work to stop — respect it.
          const userInitiated =
            info.reason === backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL
            || info.reason ===
              backgroundTaskManager.ContinuousTaskCancelReason.USER_CANCEL_REMOVE_NOTIFICATION;
          if (userInitiated) {
            return;
          }
          // A system cancel (low-speed check, policy) does NOT mean the user
          // wants to stop, so take the task back. Re-acquiring here rather than
          // waiting for the 5s poll is what makes the difference: the OS froze
          // this process ~5s after the task was gone in an on-device capture,
          // which is exactly the poll period — so a poll-driven re-acquire
          // races the freeze, and losing that race means the process is frozen
          // with no keep-alive and can never re-acquire on its own. Downloads
          // then only ran while the app was on screen.
          //
          // Backoff on THIS immediate path only: a transfer the OS considers
          // too slow gets cancelled again the moment we re-acquire, and a hot
          // loop on the background-task service is worse than a slow download.
          // (The 5s poll still retries on its own cadence — unchanged, and one
          // IPC per poll is cheap.) 10s is the documented low-speed sample
          // window.
          const now = Date.now();
          this.active = false;
          if (now - this.lastSystemCancelAt < 10000) {
            hilog.warn(0x0001, TAG,
              'Continuous task re-acquire skipped (%{public}dms since last cancel)',
              now - this.lastSystemCancelAt);
            return;
          }
          this.lastSystemCancelAt = now;
          hilog.info(0x0001, TAG, 'Continuous task re-acquire after system cancel');
          this.acquire('re-acquire after system cancel').catch((e: Error) => {
            hilog.error(0x0001, TAG,
              'Continuous task re-acquire failed: %{public}s', String(e));
          });
        });
      backgroundTaskManager.on('continuousTaskSuspend',
        (info: backgroundTaskManager.ContinuousTaskSuspendInfo) => {
          hilog.warn(0x0001, TAG,
            'Continuous task SUSPEND state=%{public}d reason=%{public}d',
            info.suspendState ? 1 : 0, info.suspendReason);
        });
      backgroundTaskManager.on('continuousTaskActive',
        (info: backgroundTaskManager.ContinuousTaskActiveInfo) => {
          hilog.info(0x0001, TAG, 'Continuous task ACTIVE id=%{public}d', info.id);
        });
    } catch (err) {
      hilog.error(0x0001, TAG,
        'continuous task state listeners unavailable: %{private}s', String(err));
    }
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
    this.registerStateListeners();
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
      // Public on purpose: the reason (e.g. "BackgroundTask is restricted",
      // permission denied) is a system string, not user data, and it is the
      // only way to tell a refused continuous task apart from a frozen process.
      hilog.error(0x0001, TAG, 'Failed to start continuous task: %{public}s', String(err));
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
