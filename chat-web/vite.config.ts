import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: "./",
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
    // WKWebView refuses to execute <script type="module"> under file://
    // (confirmed empirically, Phase 0 spike: navigation succeeds, the module
    // script never runs, no error surfaces). IIFE output is a classic
    // script -- no module/CORS semantics -- which loads fine under file://.
    // inlineDynamicImports is required because IIFE can't code-split.
    rollupOptions: {
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: "assets/[name].js",
      },
    },
  },
});
