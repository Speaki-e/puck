// Vite's HTML plugin always injects <script type="module" crossorigin ...>
// for the app entry, regardless of vite.config.ts's rollupOptions.output.format
// -- even though we build as IIFE specifically so this isn't a module. WKWebView
// refuses to execute type="module" scripts under file://, so this postbuild
// step rewrites the tag to a plain classic <script src="...">.
import { readFileSync, writeFileSync } from "node:fs";

const path = "dist/index.html";
const html = readFileSync(path, "utf8");
// defer, not just a bare classic script: type="module" scripts execute after
// the document is parsed, and main.tsx relies on that (it looks up #root,
// which lives later in the body). A classic script in <head> with no defer
// runs immediately and finds no #root yet -- React error #299.
const fixed = html.replace(/<script type="module" crossorigin src="([^"]+)"><\/script>/, '<script defer src="$1"></script>');

if (fixed === html) {
  console.error("strip-module-script-tag: no <script type=\"module\"> tag found to rewrite -- did Vite's output change?");
  process.exit(1);
}

writeFileSync(path, fixed);
console.log("stripped type=\"module\"/crossorigin from dist/index.html");
