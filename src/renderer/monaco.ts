import { loader } from "@monaco-editor/react";
import * as monaco from "monaco-editor";
import {
  javascriptDefaults,
  JsxEmit,
  ModuleKind,
  ModuleResolutionKind,
  ScriptTarget,
  typescriptDefaults,
} from "monaco-editor/languages/features/typescript/register.js";

self.MonacoEnvironment = {
  getWorker(_moduleId: string, label: string) {
    if (label === "json") {
      return new Worker(new URL("../../node_modules/monaco-editor/esm/vs/language/json/json.worker.js", import.meta.url), { type: "module" });
    }
    if (label === "css" || label === "scss" || label === "less") {
      return new Worker(new URL("../../node_modules/monaco-editor/esm/vs/language/css/css.worker.js", import.meta.url), { type: "module" });
    }
    if (label === "html" || label === "handlebars" || label === "razor") {
      return new Worker(new URL("../../node_modules/monaco-editor/esm/vs/language/html/html.worker.js", import.meta.url), { type: "module" });
    }
    if (label === "typescript" || label === "javascript") {
      return new Worker(new URL("../../node_modules/monaco-editor/esm/vs/language/typescript/ts.worker.js", import.meta.url), { type: "module" });
    }
    return new Worker(new URL("../../node_modules/monaco-editor/esm/vs/editor/editor.worker.js", import.meta.url), { type: "module" });
  },
};

loader.config({ monaco });

const diagnostics = {
  noSemanticValidation: true,
  noSuggestionDiagnostics: true,
  noSyntaxValidation: false,
};

typescriptDefaults.setDiagnosticsOptions(diagnostics);
javascriptDefaults.setDiagnosticsOptions(diagnostics);
typescriptDefaults.setCompilerOptions({
  allowNonTsExtensions: true,
  allowJs: true,
  jsx: JsxEmit.ReactJSX,
  module: ModuleKind.ESNext,
  moduleResolution: ModuleResolutionKind.NodeJs,
  target: ScriptTarget.ES2020,
});
javascriptDefaults.setCompilerOptions({
  allowNonTsExtensions: true,
  allowJs: true,
  checkJs: false,
  jsx: JsxEmit.ReactJSX,
  module: ModuleKind.ESNext,
  moduleResolution: ModuleResolutionKind.NodeJs,
  target: ScriptTarget.ES2020,
});
