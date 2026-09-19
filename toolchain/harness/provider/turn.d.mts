import type { Context, Tool, AssistantMessage, ToolCall } from './.cache/runtime/types.ts';
export type Usage = { status: 'unknown' } | { status: 'reported'; input: number; output: number; cacheRead: number; cacheWrite: number; total: number; reasoning?: number };
export type ErrorCode = 'authentication' | 'provider' | 'timeout' | 'cancelled' | 'incomplete' | 'unsupported';
export type TurnInput = { context: Context; tools: Tool[]; accessToken: string; fetch: typeof fetch; signal?: AbortSignal; deadlineMs?: number };
export type TurnResult = { kind: 'error'; error: { code: ErrorCode }; usage: Usage } | { kind: 'final'; text: string; message: AssistantMessage; usage: Usage } | { kind: 'tool'; call: ToolCall; message: AssistantMessage; usage: Usage };
export function turn(input: TurnInput): Promise<TurnResult>;
export function legacyUsage(usage: Usage): Extract<Usage, { status: 'reported' }>;
