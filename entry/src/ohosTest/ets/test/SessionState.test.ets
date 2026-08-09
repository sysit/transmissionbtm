// transmissionhm — SessionState and SessionRunState tests
//
// Cross-referenced against transmissionbtc Transmission.java state machine.
// Notable divergence: our port omits the STOPPING state (transmissionbtc has
// STATE_STOPPING=4 bitmask between RUNNING and STOPPED). We use STOPPED
// directly for synchronous stop.

import { describe, it, expect } from '@ohos/hypium';
import { SessionRunState, SessionState } from '../../../main/ets/models/SessionState';

export default function sessionStateTest(): void {
  describe('SessionRunState', () => {
    it('has_five_states', 0, (): void => {
      expect(SessionRunState.STOPPED).assertEqual(0);
      expect(SessionRunState.STARTING).assertEqual(1);
      expect(SessionRunState.RUNNING).assertEqual(2);
      expect(SessionRunState.SUSPENDING).assertEqual(3);
      expect(SessionRunState.SUSPENDED).assertEqual(4);
    });

    it('states_are_mutually_distinct', 0, (): void => {
      const values: number[] = [
        SessionRunState.STOPPED,
        SessionRunState.STARTING,
        SessionRunState.RUNNING,
        SessionRunState.SUSPENDING,
        SessionRunState.SUSPENDED,
      ];
      const unique: Set<number> = new Set();
      for (let i = 0; i < values.length; i++) {
        unique.add(values[i]);
      }
      expect(unique.size).assertEqual(5);
    });

    it('note_no_STOPPING_state_unlike_transmissionbtc', 0, (): void => {
      // transmissionbtc: STATE_STOPPING=0x04 bitmask between RUNNING/STOPPED.
      // Our port: stop() is synchronous, no STOPPING guard needed — value 4 is
      // reassigned to SUSPENDED in our sequential enum, so no member equals the
      // transmissionbtc STOPPING bit.
      expect(SessionRunState.SUSPENDED).assertEqual(4);
      // STOPPING is absent from the enum — its 5 members are STOPPED, STARTING,
      // RUNNING, SUSPENDING, SUSPENDED (see has_five_states).
    });
  });

  describe('SessionState', () => {
    it('initial_values_are_STOPPED', 0, (): void => {
      const s: SessionState = new SessionState();
      expect(s.state).assertEqual(SessionRunState.STOPPED);
      expect(s.sessionId).assertEqual(0);
      expect(s.version).assertEqual('');
      expect(s.rpcPort).assertEqual(9091);
      expect(s.peerPort).assertEqual(51413);
      expect(s.ip).assertEqual('');
    });

    it('isStopped_true_isRunning_false_initially', 0, (): void => {
      const s: SessionState = new SessionState();
      expect(s.isStopped()).assertTrue();
      expect(s.isRunning()).assertFalse();
    });

    it('isRunning_true_after_setting_RUNNING', 0, (): void => {
      const s: SessionState = new SessionState();
      s.state = SessionRunState.RUNNING;
      expect(s.isRunning()).assertTrue();
      expect(s.isStopped()).assertFalse();
    });

    it('state_transitions_are_direct_mutable', 0, (): void => {
      const s: SessionState = new SessionState();
      s.state = SessionRunState.STARTING;
      expect(s.state).assertEqual(SessionRunState.STARTING);
      s.state = SessionRunState.RUNNING;
      expect(s.state).assertEqual(SessionRunState.RUNNING);
      s.state = SessionRunState.SUSPENDED;
      expect(s.state).assertEqual(SessionRunState.SUSPENDED);
      s.state = SessionRunState.STOPPED;
      expect(s.state).assertEqual(SessionRunState.STOPPED);
    });

    it('sessionId_version_are_mutable', 0, (): void => {
      const s: SessionState = new SessionState();
      s.sessionId = 42;
      s.version = '1.0.0';
      expect(s.sessionId).assertEqual(42);
      expect(s.version).assertEqual('1.0.0');
    });
  });
}
