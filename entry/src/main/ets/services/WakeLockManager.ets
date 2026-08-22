// transmissionbtm — Wake Lock Manager (M4)
//
// Wrapper around @ohos.runningLock to prevent the system from suspending
// the process during active downloads. Acquired when any torrent is
// actively downloading, released when all torrents are idle/paused/seeding.
//
// Lifecycle:
//   acquire(reason) → hold the BACKGROUND running lock
//   release()      → unhold the lock
//   isHolding()    → check current state
//
// Only one lock is managed at a time. Repeated acquire() calls after the
// lock is already held are no-ops.

import { runningLock } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'WakeLockManager';

export class WakeLockManager {
  private lock: runningLock.RunningLock | null = null;
  private isHeld: boolean = false;

  /**
   * Acquire a BACKGROUND running lock to keep the CPU alive during
   * active BitTorrent transfers.
   *
   * @param reason Human-readable reason for the lock (logged).
   */
  async acquire(reason: string): Promise<void> {
    if (this.isHeld) {
      return;
    }
    try {
      this.lock = await runningLock.create(
        'TransmissionDownload',
        runningLock.RunningLockType.BACKGROUND
      );
      if (this.lock) {
        // hold(0) = hold indefinitely until explicitly unheld
        this.lock.hold(0);
        this.isHeld = true;
      }
      hilog.info(0x0001, TAG,
        'Wake lock acquired: %{public}s', reason);
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to acquire wake lock: %{private}s', String(err));
    }
  }

  /**
   * Release the running lock, allowing the system to suspend.
   * Safe to call when lock is not held (no-op).
   */
  release(): void {
    if (!this.isHeld || !this.lock) {
      return;
    }
    try {
      this.lock.unhold();
      this.isHeld = false;
      this.lock = null;
      hilog.info(0x0001, TAG, 'Wake lock released');
    } catch (err) {
      hilog.error(0x0001, TAG,
        'Failed to release wake lock: %{private}s', String(err));
    }
  }

  /**
   * Returns true if the running lock is currently held.
   */
  isHolding(): boolean {
    return this.isHeld;
  }
}
