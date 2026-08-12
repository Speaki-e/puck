import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const root = path.resolve("dist");
const assetsDirectory = path.join(root, "assets");
const [html, assets] = await Promise.all([
  readFile(path.join(root, "index.html"), "utf8"),
  readdir(assetsDirectory),
]);

const requireAsset = (description, predicate) => {
  if (!assets.some(predicate)) throw new Error(`Renderer build 누락: ${description}`);
};

requireAsset("애플리케이션 JavaScript", (file) => /^index-.*\.js$/.test(file));
requireAsset("애플리케이션 CSS", (file) => /^index-.*\.css$/.test(file));
requireAsset("Monaco editor worker", (file) => /^editor\.worker-.*\.js$/.test(file));
requireAsset("Monaco TypeScript worker", (file) => /^ts\.worker-.*\.js$/.test(file));
requireAsset("로컬 Geist 글꼴", (file) => /geist.*\.woff2$/i.test(file));

if (!html.includes('./assets/') || /<(?:script|link)[^>]+(?:src|href)=["']https?:\/\//i.test(html)) {
  throw new Error("Renderer 진입점은 패키지 내부 상대 경로만 사용해야 합니다");
}

console.log(`Renderer 정적 번들 검증 완료: ${assets.length}개 asset`);
