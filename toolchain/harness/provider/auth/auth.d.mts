export type Outcome = 'authenticated' | 'missing' | 'cancelled' | 'timeout' | 'conflict' | 'storage_failure' | 'provider_failure';
export type Options = { signal?: AbortSignal; deadlineMs?: number };
export type Credential = { type: 'oauth'; access: string; refresh: string; expires: number; accountId: string };
export type DeviceEvent = { type: 'device_code'; verificationUri: 'https://auth.openai.com/codex/device'; userCode: string; intervalSeconds: number; expiresInSeconds: number };
export type OAuth = {
  login(interaction: { signal: AbortSignal; prompt(prompt: unknown): Promise<string>; notify(event: unknown): void }): Promise<Credential>;
  refresh(credential: Credential, signal: AbortSignal): Promise<Credential>;
  toAuth(credential: Credential): Promise<{ apiKey: string }>;
};
export function installTransport(transport: typeof fetch): void;
export function loadOAuth(runtimeDirectory: string): Promise<OAuth>;
export function createAuth(config: {
  directory: string; candidateRoots: string[]; oauth: OAuth; operatorSink?: (event: DeviceEvent) => void;
}): {
  login(options?: Options): Promise<{ code: Outcome }>;
  logout(options?: Options): Promise<{ code: Outcome }>;
  status(options?: Options): Promise<{ providerId: 'openai-codex'; state: 'authenticated' | 'missing' | 'expired' | 'unavailable' }>;
  resolve(options?: Options): Promise<{ code: Outcome; accessToken?: string }>;
  credentialStore: {
    read(providerId: string, options?: Options): Promise<Credential | undefined>;
    list(options?: Options): Promise<readonly { providerId: string; type: 'oauth' }[]>;
    modify(providerId: string, fn: (current: Credential | undefined) => Promise<Credential | undefined>, options?: Options): Promise<Credential | undefined>;
    delete(providerId: string, options?: Options): Promise<void>;
  };
};
