import type { BeforeMount } from "@monaco-editor/react";

export const MONACO_FONT_FAMILY = "'Geist Mono', 'SFMono-Regular', Consolas, monospace";

export const configureMonaco: BeforeMount = (monaco) => {
  monaco.editor.defineTheme("workspace-dark", {
    base: "vs-dark",
    inherit: true,
    rules: [
      { token: "comment", foreground: "737373", fontStyle: "italic" },
      { token: "keyword", foreground: "C084FC" },
      { token: "string", foreground: "7DD3FC" },
      { token: "number", foreground: "FBBF24" },
      { token: "type", foreground: "60A5FA" },
    ],
    colors: {
      // v2 (2026-08-14): these mirror ClientPalette/CSS token values --
      // canvas #0a0a0a, surface #131313, hairline #242424 -- rather than
      // the old v1 hex literals (docs/decisions.md).
      "editor.background": "#0a0a0a",
      "editor.foreground": "#e7e7e7",
      "editorLineNumber.foreground": "#4f4f4f",
      "editorLineNumber.activeForeground": "#a3a3a3",
      "editor.lineHighlightBackground": "#131313",
      "editor.selectionBackground": "#173f70",
      "editor.inactiveSelectionBackground": "#182c43",
      "editorIndentGuide.background1": "#252525",
      "editorIndentGuide.activeBackground1": "#404040",
      "editorCursor.foreground": "#f5f5f5",
      "editorWhitespace.foreground": "#242424",
      "editorGutter.background": "#0a0a0a",
    },
  });
};
