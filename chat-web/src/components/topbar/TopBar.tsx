import { SessionSelector } from "./SessionSelector";
import { EditorToggleButton } from "./EditorToggleButton";
import { SettingsButton } from "./SettingsButton";

export function TopBar() {
  return (
    <header className="flex items-center gap-2 px-4 pt-7 pb-2">
      <SessionSelector />
      <div className="flex-1" />
      <EditorToggleButton />
      <SettingsButton />
    </header>
  );
}
