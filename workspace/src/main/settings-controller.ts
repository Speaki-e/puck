import { ipcMain } from "electron";
import type { SettingsStore } from "./settings-store.js";
import type { SecretStore } from "./secret-store.js";
import type { WorkspaceRegistry } from "./workspace-registry.js";
import type { WindowStateStore } from "./window-state-store.js";
import type { JsonlLogger } from "./logger.js";
import type { RecentProject, SettingsSnapshot, WorkspaceSettings } from "../shared/settings-contract.js";

const IPC_CHANNELS = ["settings:get", "settings:update", "settings:set-api-key", "settings:clear-api-key"] as const;

/**
 * 설정 화면(W7)의 백엔드: API 키·모델·최근 프로젝트·창 크기·파일 제한·로그 수준.
 * 폴백 셸(IPC)에서만 노출한다(plan/03_workspace.md 4.5) -- pet-app 쪽 설정은 02_pet-app.md 몫이라
 * EditorGateway/게이트웨이 WorkspaceApi에는 이 기능을 올리지 않는다.
 * API 키 저장은 이주한이 만든 safeStorage 기반 SecretStore를 그대로 재사용한다 -- 새 암호화
 * 로직을 만들지 않는다. 렌더러로는 키의 존재 여부(hasApiKey)만 돌려주고 값 자체는 절대 보내지
 * 않는다.
 */
export class SettingsController {
  constructor(
    private readonly settings: SettingsStore,
    private readonly secrets: SecretStore,
    private readonly registry: WorkspaceRegistry,
    private readonly windowStateStore: WindowStateStore,
    private readonly logger: JsonlLogger,
    private readonly onSettingsChanged?: (settings: WorkspaceSettings) => void,
  ) {}

  installIpc(): void {
    ipcMain.handle("settings:get", () => this.snapshot());

    ipcMain.handle("settings:update", async (_event, patch: Partial<WorkspaceSettings>) => {
      const updated = await this.settings.update(patch);
      this.onSettingsChanged?.(updated);
      await this.logger.write("info", "settings_updated", {
        logLevel: updated.logLevel,
        fileSizeLimitBytes: updated.fileSizeLimitBytes,
      });
      return this.snapshot();
    });

    ipcMain.handle("settings:set-api-key", async (_event, key: unknown) => {
      if (typeof key !== "string" || !key.trim()) throw new Error("API 키가 비어 있습니다");
      await this.secrets.set("claudeApiKey", key.trim());
      // 값 자체는 로그에 절대 남기지 않는다 -- REDACTED_KEYS 마스킹과 별개로 아예 안 넘긴다.
      await this.logger.write("info", "api_key_updated", {});
      return { hasApiKey: true };
    });

    ipcMain.handle("settings:clear-api-key", async () => {
      await this.secrets.delete("claudeApiKey");
      await this.logger.write("info", "api_key_cleared", {});
      return { hasApiKey: false };
    });
  }

  close(): void {
    for (const channel of IPC_CHANNELS) ipcMain.removeHandler(channel);
  }

  private async snapshot(): Promise<SettingsSnapshot> {
    const [hasApiKey, windowState] = await Promise.all([
      this.secrets.get("claudeApiKey").then(Boolean),
      this.windowStateStore.load(),
    ]);
    const recentProjects: RecentProject[] = this.registry.list()
      .filter((record): record is typeof record & { realProjectPath: string } => Boolean(record.realProjectPath))
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .map((record) => ({ id: record.id, name: record.name, projectPath: record.realProjectPath, updatedAt: record.updatedAt }));
    return {
      ...this.settings.current,
      hasApiKey,
      recentProjects,
      windowSize: windowState ? { width: windowState.width, height: windowState.height } : undefined,
    };
  }
}
