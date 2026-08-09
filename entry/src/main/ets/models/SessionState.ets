// transmissionhm — SessionState model

export enum SessionRunState {
  STOPPED = 0, STARTING = 1, RUNNING = 2,
  SUSPENDING = 3, SUSPENDED = 4,
}

export class SessionState {
  state: SessionRunState = SessionRunState.STOPPED;
  sessionId: number = 0;
  version: string = '';
  rpcPort: number = 9091;
  peerPort: number = 51413;
  ip: string = '';
  isRunning(): boolean { return this.state === SessionRunState.RUNNING; }
  isStopped(): boolean { return this.state === SessionRunState.STOPPED; }
}
