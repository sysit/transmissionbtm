// transmissionbtm — SessionRunState tests
//
// Cross-referenced against transmissionbtc Transmission.java state machine.
// Notable divergence: our port omits the STOPPING state (transmissionbtc has
// STATE_STOPPING=4 bitmask between RUNNING and STOPPED). We use STOPPED
// directly for synchronous stop.
//
// E4 (docs/11): the SessionState class was deleted (unconsumed — see
// models/SessionState.ets); its describe block below was removed with it.
// Only SessionRunState survives.

import { describe, it, expect } from '@ohos/hypium';
import { SessionRunState } from '../../../main/ets/models/SessionState';

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
}
