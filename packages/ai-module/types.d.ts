import type {
  Attachment,
  Context,
  JSONValue,
  ToolDefinition,
  ToolExecutionResult,
  ToolExecutor,
  ToolExecutorKind,
  ToolResultErrorCode,
} from "@speaki-e/protocol";

export type { Attachment, Context, ToolExecutor, ToolExecutionResult } from "@speaki-e/protocol";
export type DispatchableExecutorKind = Exclude<ToolExecutorKind, "ai-module">;
export type ExecutorMap = Partial<Record<DispatchableExecutorKind, ToolExecutor>>;
export type LocalToolErrorCode = ToolResultErrorCode | "invalid_input" | "not_implemented_yet" | "executor_not_available";
export interface ClientOptions { apiKey: string; model: string; baseURL?: string; executors: ExecutorMap; }
export interface ToolCallInfo { id: string; name: string; input: unknown; executor?: ToolExecutorKind; }
export interface ToolResultInfo { id: string; name: string; ok: boolean; content: string; }
export interface RunCallbacks {
  onTextChunk(text: string): void;
  onDone(ok: boolean, summary?: string): void;
  onToolCallStart?(call: ToolCallInfo): void;
  onToolResult?(result: ToolResultInfo): void;
  onApprovalRequired?(summary: string, resolve: (approved: boolean) => void): void;
  onSessionCreated?(sessionId: string, title: string): void;
}
export interface AiClient {
  run(command: string, callbacks: RunCallbacks, signal?: AbortSignal): Promise<void>;
  run(command: string, sessionId: string, context: Context, callbacks: RunCallbacks, attachments?: Attachment[], signal?: AbortSignal): Promise<void>;
}
export function createClient(options: ClientOptions): AiClient;
export function getToolDef(name: string): ToolDefinition | undefined;
export function allTools(): readonly ToolDefinition[];
export function validateArgs(def: ToolDefinition, args: unknown): string | undefined;
export function toAnthropicTools(): unknown[];
export function loadBasePrompt(): string;
export function buildSystemPrompt(basePrompt: string, context: Context, sessionBrief?: string): string;
export function loadWhitelist(): unknown;
export function needsApproval(def: ToolDefinition, args: unknown, whitelist: unknown): boolean;
export function isWhitelistedCommand(command: string | undefined, whitelist: unknown): boolean;
export const DEFAULT_SESSION_ID: string;
export class SessionStore {}
