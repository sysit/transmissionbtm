import { describe, it, expect } from 'vitest';
import { SessionRunState } from '../entry/src/main/ets/models/SessionState.ets';

describe('SessionRunState', () => {
  it('has five states with correct values', () => {
    expect(SessionRunState.STOPPED).toBe(0);
    expect(SessionRunState.STARTING).toBe(1);
    expect(SessionRunState.RUNNING).toBe(2);
    expect(SessionRunState.SUSPENDING).toBe(3);
    expect(SessionRunState.SUSPENDED).toBe(4);
  });
});
