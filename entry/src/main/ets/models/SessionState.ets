// transmissionbtm — SessionState model

// E4 (docs/11): the SessionState class was provided by Index (@Provide) but no
// page ever consumed it — removed. SessionRunState stays: TransmissionSession
// uses it as its run-state enum.
export enum SessionRunState {
  STOPPED = 0, STARTING = 1, RUNNING = 2,
  SUSPENDING = 3, SUSPENDED = 4,
}
