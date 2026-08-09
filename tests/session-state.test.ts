import { describe, it, expect } from 'vitest';
import { SessionState, SessionRunState } from '../entry/src/main/ets/models/SessionState.ets';

describe('SessionRunState', () => {
  it('has five states with correct values', () => {
    expect(SessionRunState.STOPPED).toBe(0);
    expect(SessionRunState.STARTING).toBe(1);
    expect(SessionRunState.RUNNING).toBe(2);
    expect(SessionRunState.SUSPENDING).toBe(3);
    expect(SessionRunState.SUSPENDED).toBe(4);
  });
});

describe('SessionState', () => {
  it('defaults to STOPPED state', () => {
    const state = new SessionState();
    expect(state.state).toBe(SessionRunState.STOPPED);
    expect(state.isStopped()).toBe(true);
    expect(state.isRunning()).toBe(false);
  });

  it('defaults sessionId to 0', () => {
    expect(new SessionState().sessionId).toBe(0);
  });

  it('defaults version to empty string', () => {
    expect(new SessionState().version).toBe('');
  });

  it('has correct default ports', () => {
    const state = new SessionState();
    expect(state.rpcPort).toBe(9091);
    expect(state.peerPort).toBe(51413);
  });

  it('isRunning returns true only for RUNNING', () => {
    const state = new SessionState();
    state.state = SessionRunState.RUNNING;
    expect(state.isRunning()).toBe(true);
    expect(state.isStopped()).toBe(false);
  });

  it('isStopped returns true only for STOPPED', () => {
    const state = new SessionState();
    state.state = SessionRunState.SUSPENDED;
    expect(state.isStopped()).toBe(false);
    state.state = SessionRunState.STOPPED;
    expect(state.isStopped()).toBe(true);
  });

  it('can transition through all states', () => {
    const state = new SessionState();
    state.state = SessionRunState.STARTING;
    expect(state.isRunning()).toBe(false);
    expect(state.isStopped()).toBe(false);
    state.state = SessionRunState.RUNNING;
    expect(state.isRunning()).toBe(true);
    state.state = SessionRunState.SUSPENDING;
    state.state = SessionRunState.SUSPENDED;
    state.state = SessionRunState.STOPPED;
    expect(state.isStopped()).toBe(true);
  });

  it('ip defaults to empty', () => expect(new SessionState().ip).toBe(''));
});
