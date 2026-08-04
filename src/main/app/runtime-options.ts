export interface RuntimeOptions {
  headless: boolean;
  projectPath?: string;
  bridgeSocket?: string;
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
  };
}
