/**
 * Avatar manifest.json schema (protocol docs/avatar-manifest.md, plan/01_protocol.md
 * section 6). Mirrors pet-app/PetAgent/Avatar/AvatarManifest.swift.
 */

export type AvatarType = "usdz" | "video" | "sprites";

export interface Hitbox {
  width: number;
  height: number;
}

/**
 * A value in the clips table.
 *
 * For `type: usdz`/`sprites`, a plain string is a file stem living alongside
 * manifest.json (e.g. "walk" -> Avatars/{name}/walk.usdz) -- NOT an animation
 * name inside one shared model. RealityKit effectively only plays a usdz's
 * first animation regardless of how many are baked in, so this is one usdz
 * file per clip, not one usdz with many named animations. See
 * pet-app/docs/avatar-spec.md for the full external-creator requirements.
 *
 * For `type: video`, the value is instead a { in, out } timecode range (seconds).
 */
export type ClipReference = string | { in: number; out: number };

/** Missing clips other than these fall back to idle; these two are mandatory. */
export const REQUIRED_CLIPS = ["idle", "walk"] as const;

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
  /** First implementation only supports "usdz"; "video"/"sprites" are reserved. */
  type: AvatarType;
  /**
   * Multiplier applied to the root entity so that raw mesh height * scale ~= 1
   * unit (1 unit == 100 screen px). Prefer normalizing the source mesh to 1
   * unit (scale = 1.0) -- scale here is a correction fallback, not the primary
   * mechanism (scale = 1 / raw mesh height).
   */
  scale: number;
  hitbox: Hitbox;
  clips: Record<string, ClipReference>;
  /** Keys are a mix of clip names and SoundEventKey values -- see SoundEventKey. */
  sounds: Record<string, string>;
}
