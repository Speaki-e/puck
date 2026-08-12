const { app, BrowserWindow } = require("electron");
const { writeFileSync } = require("node:fs");
const path = require("node:path");

app.disableHardwareAcceleration();

void app.whenReady().then(() => {
  return (async () => {
  const source = path.resolve("assets/icon.svg");
  const target = path.resolve("assets/icon.png");
  const window = new BrowserWindow({ width: 512, height: 512, show: false, frame: false, useContentSize: true });
  await window.loadFile(source);
  const image = await window.webContents.capturePage({ x: 0, y: 0, width: 512, height: 512 });
  writeFileSync(target, image.toPNG());
  window.destroy();
  console.log(`Windows 아이콘 생성 완료: ${target}`);
  })();
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => app.quit());
