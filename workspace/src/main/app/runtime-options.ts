export interface RuntimeOptions {
  headless: boolean;
  projectPath?: string;
  bridgeSocket?: string;
  /**
   * code_editor를 ACP(Claude Code) 대신 OpenAI 툴 루프로 실행한다. 키는
   * OPENAI_API_KEY, 모델은 OPENAI_MODEL(기본 gpt-4o) 환경변수에서 읽는다 --
   * pet-app의 F15 두뇌와 같은 이름을 쓰므로 .env 하나를 공유할 수 있다.
   */
  openAiCodeEditor: boolean;
}

function argumentValue(argv: readonly string[], name: string): string | undefined {
  const index = argv.indexOf(name);
  const value = index >= 0 ? argv[index + 1] : undefined;
  return value && !value.startsWith("--") ? value : undefined;
}

/** Parse only Workspace-owned command-line flags; Electron/Chromium flags are ignored. */
export function parseRuntimeOptions(argv: readonly string[] = process.argv): RuntimeOptions {
  return {
    headless: argv.includes("--headless"),
    projectPath: argumentValue(argv, "--project"),
    bridgeSocket: argumentValue(argv, "--bridge-socket"),
    openAiCodeEditor: argv.includes("--openai-code-editor"),
  };
}
