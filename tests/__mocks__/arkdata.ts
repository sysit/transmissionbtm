// Mock for @kit.ArkData (preferences)
// @ohos.data.preferences is unavailable in the Node.js vitest runtime.
// Provides an in-memory store with the subset PreferencesManager uses:
//   preferences.getPreferences(context, name) -> store
//   store.get(key, def?) / put(key, value) / has(key) / flush() / clear()
// Each getPreferences call returns a fresh store so tests stay isolated.

class InMemoryPreferences {
  private data = new Map<string, unknown>();

  async get(key: string, def: unknown = null): Promise<unknown> {
    return this.data.has(key) ? this.data.get(key) : def;
  }

  async put(key: string, value: unknown): Promise<void> {
    this.data.set(key, value);
  }

  async has(key: string): Promise<boolean> {
    return this.data.has(key);
  }

  async flush(): Promise<void> {
    // No-op: in-memory store needs no persistence.
  }

  async clear(): Promise<void> {
    this.data.clear();
  }
}

export const preferences = {
  async getPreferences(_context: unknown, _name: string): Promise<InMemoryPreferences> {
    return new InMemoryPreferences();
  },
};
