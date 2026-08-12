/**
 * Avatar manifest.json schema (protocol docs/avatar-manifest.md, plan/01_protocol.md
 * section 6). Mirrors pet-app/Puck/Avatar/AvatarManifest.swift.
 *
 * Primary avatar type is 2D sprites (PNG) rather than 3D usdz.
 * `bounce_intensity` and `emotions` are additive, optional fields --
 * non-breaking, MINOR version.
 */

export type AvatarType = "usdz" | "video" | "sprites";

export interface Hitbox {
  width: number;
  height: number;
}

/**
 * A value in the clips table.
 *
 * For `type: sprites`, a plain string is a file stem living alongside
 * manifest.json (e.g. "walk" -> Avatars/{name}/walk.png). For `type: usdz`,
 * the same stem convention pointed at a usdz instead -- one usdz file per
 * clip, not one usdz with many named animations, since RealityKit only ever
 * plays a usdz's first animation regardless of how many it contains. See
 * pet-app/docs/avatar-spec.md for the full external-creator requirements.
 *
 * For `type: video`, the value is instead a { in, out } timecode range (seconds).
 */
export type ClipReference = string | { in: number; out: number };

/**
 * idle is the only required clip -- 2026-07-29's 2D switch relaxed this from
 * {idle, walk} so a single base illustration is enough to run. Every other
 * clip (including walk) falls back to idle when absent.
 */
export const REQUIRED_CLIPS = ["idle"] as const;

/**
 * sounds keys mix clip names (played on FSM state entry) and event names
 * (played on socket events, protocol events.ts BridgeEvent). Both lookups
 * hit this same table. The event-name keys pair with the events those names
 * name -- e.g. "await_approval" is the SFX for the await_approval BridgeEvent.
 */
export type SoundEventKey =
  | "app_launch"
  | "task_success"
  | "task_fail"
  | "await_approval"
  | "listen_start";

export interface AvatarManifest {
  schema_version: number;
  name: string;
  /** 2026-07-29: "sprites" is the primary implementation; usdz/video are interface-only. */
  type: AvatarType;
  /**
   * Multiplier applied to the root entity/layer so that raw source height *
   * scale ~= 1 unit (1 unit == 100 screen px). Prefer normalizing the source
   * asset to 1 unit (scale = 1.0) -- scale here is a correction fallback, not
   * the primary mechanism (scale = 1 / raw source height).
   */
  scale: number;
  /**
   * Optional, sprites-only. 0.0-1.0 multiplier for pet-app's code-driven
   * procedural squash-and-stretch "bounce" motion (idle breathing, walk
   * bounce, land squash-recover, kick anticipation-stretch, ...) -- there are
   * no animation frames to ship, so this tunes an effect pet-app applies on
   * top of a single static image. Absent means pet-app's own default; 0 means
   * fully static. Has no effect for usdz/video avatars.
   */
  bounce_intensity?: number;
  hitbox: Hitbox;
  clips: Record<string, ClipReference>;
  /**
   * Optional. Same stem-dictionary shape as `clips`, keyed by emotion name
   * (e.g. "happy", "thinking"). When a socket event maps to an emotion this
   * table has an entry for, pet-app swaps to that image; otherwise it keeps
   * whatever clip is currently showing. Entirely optional -- an avatar with
   * only a base image needs no `emotions` table at all.
   */
  emotions?: Record<string, ClipReference>;
  /** Keys are a mix of clip names and SoundEventKey values -- see SoundEventKey. */
  sounds: Record<string, string>;
}
