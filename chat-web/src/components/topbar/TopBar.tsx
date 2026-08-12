import { SessionSelector } from "./SessionSelector";
import { EditorToggleButton } from "./EditorToggleButton";
import { SettingsButton } from "./SettingsButton";

// pt-7 (28px) clears the native window's traffic lights -- this pane sits at
// the window's top-left (where they are), unlike the editor pane on the
// right, which is why the two top bars don't align when both show at once.
// That offset has to live in the webview's own content (not a native
// SwiftUI-level padding wrapping the whole webview): the dark background
// behind the traffic lights has to come from *this view's* fill reaching
// y=0, only its content padded away from the edge -- pushing the whole
// webview frame down instead would leave the window's own (light, default)
// background showing through behind the traffic lights.
export function TopBar() {
  return (
    <header className="flex items-center gap-2 border-b border-hairline px-4 pt-7 pb-2">
      <SessionSelector />
      <div className="flex-1" />
      <EditorToggleButton />
      <SettingsButton />
    </header>
  );
}
