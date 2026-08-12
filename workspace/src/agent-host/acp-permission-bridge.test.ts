import { describe, expect, it, vi } from "vitest";
import type * as acp from "@agentclientprotocol/sdk";
import { createAcpPermissionResolver } from "./acp-permission-bridge.js";

function requestWithOptions(options: acp.PermissionOption[]): acp.RequestPermissionRequest {
  return {
    sessionId: "sess-1",
    toolCall: { toolCallId: "tc-1", title: "빌드 폴더 삭제" },
    options,
  } as acp.RequestPermissionRequest;
}

describe("createAcpPermissionResolver", () => {
  it("승인되면 allow_once 옵션을 선택한다", async () => {
    const requestApproval = vi.fn().mockResolvedValue(true);
    const resolver = createAcpPermissionResolver({ requestApproval }, { runId: "r1", workspaceId: "w1", sessionId: "s1" });
    const response = await resolver(requestWithOptions([
      { optionId: "allow-once", name: "허용", kind: "allow_once" },
      { optionId: "reject-once", name: "거부", kind: "reject_once" },
    ]));
    expect(response).toEqual({ outcome: { outcome: "selected", optionId: "allow-once" } });
    expect(requestApproval).toHaveBeenCalledWith(expect.objectContaining({
      runId: "r1",
      workspaceId: "w1",
      sessionId: "s1",
      source: "acp",
      summary: "빌드 폴더 삭제",
    }));
  });

  it("거부되면 reject_once 옵션을 선택한다", async () => {
    const requestApproval = vi.fn().mockResolvedValue(false);
    const resolver = createAcpPermissionResolver({ requestApproval }, { runId: "r1", workspaceId: "w1", sessionId: "s1" });
    const response = await resolver(requestWithOptions([
      { optionId: "allow-once", name: "허용", kind: "allow_once" },
      { optionId: "reject-once", name: "거부", kind: "reject_once" },
    ]));
    expect(response).toEqual({ outcome: { outcome: "selected", optionId: "reject-once" } });
  });

  it("once 옵션이 없으면 always 옵션으로 물러선다", async () => {
    const requestApproval = vi.fn().mockResolvedValue(true);
    const resolver = createAcpPermissionResolver({ requestApproval }, { runId: "r1", workspaceId: "w1", sessionId: "s1" });
    const response = await resolver(requestWithOptions([
      { optionId: "allow-always", name: "항상 허용", kind: "allow_always" },
    ]));
    expect(response).toEqual({ outcome: { outcome: "selected", optionId: "allow-always" } });
  });

  it("옵션이 없으면 cancelled로 응답한다", async () => {
    const requestApproval = vi.fn().mockResolvedValue(true);
    const resolver = createAcpPermissionResolver({ requestApproval }, { runId: "r1", workspaceId: "w1", sessionId: "s1" });
    const response = await resolver(requestWithOptions([]));
    expect(response).toEqual({ outcome: { outcome: "cancelled" } });
  });
});
