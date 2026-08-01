import { access, readdir, stat } from "node:fs/promises";
import path from "node:path";

const release = path.resolve("release");
const unpacked = path.join(release, "win-unpacked");
const resources = path.join(unpacked, "resources");
const required = [
  path.join(unpacked, "Workspace.exe"),
  path.join(resources, "app.asar"),
  path.join(resources, "app.asar.unpacked", "dist-main", "agent-host", "index.cjs"),
  path.join(resources, "app.asar.unpacked", "node_modules", "@agentclientprotocol", "claude-agent-acp", "dist", "index.js"),
  path.join(resources, "app.asar.unpacked", "node_modules", "@anthropic-ai", "claude-agent-sdk-win32-x64", "claude.exe"),
];

await Promise.all(required.map(async (file) => {
  await access(file);
  if ((await stat(file)).size === 0) throw new Error(`빈 패키지 파일: ${file}`);
}));

const installer = (await readdir(release)).find((file) => /^Workspace Setup .*\.exe$/.test(file));
if (!installer) throw new Error("Windows NSIS 설치 파일을 찾지 못했습니다");

console.log(`Windows 패키지 검증 완료: ${installer}, Agent Host, Claude ACP, claude.exe`);
