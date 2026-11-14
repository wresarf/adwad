// Timeline of "The Last Noob": every shot, camera, pose and event, timed to the narration (voice/lines.json).
// Same contract as the package's story.ts: SHOTS (id, a/b frames), FLASH_AT, KICKS, per-shot camera keys with
// smootherstep glides and a creeping push-in on every hold, and visual reactions landing 0-3 frames before their word.
import lines from "../voice/lines.json";
import type { Pose, Face } from "./Blocky";
import { CABIN, GATE_Z } from "./World";

export const FPS = 30;
export const TOTAL = Math.ceil(lines.duration * FPS);
type V3 = [number, number, number];
type Line = (typeof lines.lines)[number];
const LN: Record<string, Line> = Object.fromEntries(lines.lines.map((l) => [l.id, l]));
export const L = (id: string) => LN[id];
/** start time of word i of a line (seconds), minus a 2-frame lead so reactions land just before the word */
export const W = (id: string, i: number) => LN[id].words[Math.min(i, LN[id].words.length - 1)].s - 2 / FPS;
export const LINES = lines.lines;

// ---------------------------------------------------------------- maths
export const clamp = (x: number, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const ss = (a: number, b: number, t: number) => {
  const u = clamp((t - a) / (b - a));
  return u * u * u * (u * (u * 6 - 15) + 10);
};
export const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
const lv = (a: V3, b: V3, u: number): V3 => [lerp(a[0], b[0], u), lerp(a[1], b[1], u), lerp(a[2], b[2], u)];
const hash = (n: number) => {
  const x = Math.sin(n * 127.1) * 43758.5453;
  return x - Math.floor(x);
};

// ---------------------------------------------------------------- shots
// boundaries sit 2 frames before the first word of the line that opens the shot
const at = (id: string, i = 0) => Math.round(W(id, i) * FPS);
export const SHOTS = [
  { id: 1, a: 0, b: at("hook2", 0), name: "locked out" },
  { id: 2, a: at("hook2", 0), b: at("night", 0), name: "knock from inside" },
  { id: 3, a: at("night", 0), b: at("night", 6), name: "establishing" },
  { id: 4, a: at("night", 6), b: at("nonoobs", 0), name: "the vote" },
  { id: 5, a: at("nonoobs", 0), b: at("gate", 0), name: "no noobs" },
  { id: 6, a: at("gate", 0), b: at("creak", 0), name: "waiting at the gate" },
  { id: 7, a: at("creak", 0), b: at("window", 0), name: "something huge" },
  { id: 8, a: at("window", 0), b: at("wait", 0), name: "faces at the window" },
  { id: 9, a: at("wait", 0), b: at("wall", 0), name: "no shadow" },
  { id: 10, a: at("wall", 0), b: at("wall", 6), name: "looks back" },
  { id: 11, a: at("wall", 6), b: at("yousee", 0), name: "the wall shadow" },
  { id: 12, a: at("yousee", 0), b: at("yousee", 9), name: "cardboard decoy" },
  { id: 13, a: at("yousee", 9), b: at("fire", 0), name: "bait cutaway" },
  { id: 14, a: at("fire", 0), b: at("lantern", 0), name: "by the fire" },
  { id: 15, a: at("lantern", 0), b: at("reveal", 0), name: "lantern flash" },
  { id: 16, a: at("reveal", 0), b: at("door", 0), name: "disguise flickers" },
  { id: 17, a: at("door", 0), b: at("escape", 0), name: "back door" },
  { id: 18, a: at("escape", 0), b: at("welcome", 0), name: "sunrise escape" },
  { id: 19, a: at("welcome", 0), b: at("twist", 0), name: "welcome" },
  { id: 20, a: at("twist", 0), b: TOTAL, name: "two shadows" },
];
export const XFADE: Record<number, number> = { 18: 8 };
export const FLASH_AT = at("night", 0) - 3;
export const LANTERN_FLASH = W("lantern", 8);
const KNOCKS = [W("hook2", 2), W("hook2", 2) + 0.26, W("hook2", 2) + 0.5];
const SLAM1 = 0.62, SLAM2 = W("nonoobs", 5) + 0.12;
const KICK_DOOR = W("door", 1);
// impact flip-shakes [time, strength]
export const KICKS: [number, number][] = [[SLAM1, 1], ...KNOCKS.map((k) => [k, 0.55] as [number, number]), [SLAM2, 0.8], [W("creak", 7), 0.35], [LANTERN_FLASH, 0.6], [KICK_DOOR, 1.1]];

export const shotAt = (f: number) => SHOTS.find((s) => f >= s.a && f < s.b) ?? SHOTS[SHOTS.length - 1];

// ---------------------------------------------------------------- state
export type Cam = { pos: V3; look: V3; fov: number; roll?: number };
export type Actor = { key: string; who: string; pose: Pose; shadow?: boolean; flicker?: number };
export type State = {
  shot: number; t: number; dawn: number;
  cam: Cam;
  actors: Actor[];
  wallShadow: Pose | null; // the impostor's shadow on the back wall (posed on its own)
  ghostShadow: { pose: Pose; opacity: number } | null; // the twist: a second shadow with no body
  decoy: { x: number; z: number; walk: number; eyes: number; yaw: number; collapse: number; visible: boolean };
  cabin: { frontDoor: number; backDoor: number; roof: boolean; fire: number; frontWall: boolean };
  gate: number; sway: number;
  lantern: { on: number; pos: V3 } | null;
  beam: number; flash: number; title: number; interior: number; moonPatch: number; hook: number;
};

type Key = { t: number; pos: V3; look: V3; fov?: number; roll?: number };
// smootherstep glide between keys; 'creep' pushes in toward the look point over the shot (no static holds)
function camKeys(t: number, t0: number, keys: Key[], creep = 0.06): Cam {
  let c: Cam = { pos: keys[0].pos, look: keys[0].look, fov: keys[0].fov ?? 40, roll: keys[0].roll ?? 0 };
  for (let i = 1; i < keys.length; i++) {
    const a = keys[i - 1], b = keys[i];
    if (t <= a.t) break;
    const u = ss(a.t, b.t, t);
    c = { pos: lv(a.pos, b.pos, u), look: lv(a.look, b.look, u), fov: lerp(a.fov ?? 40, b.fov ?? a.fov ?? 40, u), roll: lerp(a.roll ?? 0, b.roll ?? 0, u) };
  }
  const k = clamp((t - t0) * creep, 0, 0.3);
  c.pos = lv(c.pos, c.look, k);
  return c;
}

// walk along a path of points at speed (m/s); returns position, yaw and walk phase
function walkPath(pts: V3[], t: number, t0: number, speed: number, cadence = 1.6) {
  const d = Math.max(0, t - t0) * speed;
  let acc = 0;
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1], b = pts[i];
    const seg = Math.hypot(b[0] - a[0], b[2] - a[2]);
    if (d <= acc + seg || i === pts.length - 1) {
      const u = clamp((d - acc) / seg);
      const moving = t > t0 && u < 1;
      return { x: lerp(a[0], b[0], u), z: lerp(a[2], b[2], u), yaw: Math.atan2(b[0] - a[0], b[2] - a[2]), walk: moving ? d / (cadence * 0.9) : 0, moving };
    }
    acc += seg;
  }
  const e = pts[pts.length - 1];
  return { x: e[0], z: e[2], yaw: 0, walk: 0, moving: false };
}

const blink = (t: number, seed: number): boolean => {
  const period = 1.2 + hash(seed) * 1.4;
  return (t + hash(seed + 3) * period) % period < 0.13;
};
const face = (t: number, seed: number, f: Face): Face => (blink(t, seed) && f !== "void" && f !== "scared" ? "sly" : f);

// pros' standing spots
const WIN_Z = CABIN.D / 2 - 0.62;
const PRO_WIN: Record<string, V3> = { red: [0.75, 0, WIN_Z], green: [1.7, 0, WIN_Z], blue: [2.65, 0, WIN_Z] };
const STOOL: V3 = [-2.25, 0.33, -1.2];
const NOOB_CRATE: V3 = [2.7, 0.42, GATE_Z - 0.75];

export function stateAt(f: number): State {
  const t = f / FPS;
  const shot = shotAt(f);
  const t0 = shot.a / FPS;
  const S: State = {
    shot: shot.id, t, dawn: 0,
    cam: { pos: [10, 8, 20], look: [0, 1, 0], fov: 40 },
    actors: [], wallShadow: null, ghostShadow: null,
    decoy: { x: 0, z: 44, walk: 0, eyes: 0, yaw: Math.PI, collapse: 0, visible: false },
    cabin: { frontDoor: 0, backDoor: 0, roof: true, fire: 1, frontWall: true },
    gate: 0, sway: 0, lantern: null, beam: 0, flash: 0, title: 0, interior: 0, moonPatch: 0, hook: 0,
  };
  const add = (key: string, who: string, pose: Pose, extra: Partial<Actor> = {}) => S.actors.push({ key, who, pose, shadow: true, ...extra });
  const sitPurple = (fc: Face = "neutral", headYaw = 0) =>
    add("purple", "purple", { x: STOOL[0], y: STOOL[1], z: STOOL[2], yaw: -Math.PI / 2 + 0.9, sit: 1, armL: 0.5, armR: 0.5, headYaw, face: face(t, 4, fc) }, { shadow: false });
  const prosAtWindow = (fc: Face = "scared", lean = 0.12) => {
    for (const [k, p] of Object.entries(PRO_WIN)) add(k, k, { x: p[0], z: p[2], yaw: 0, lean, armL: 0.9, armR: 0.9, armLz: 0.1, armRz: 0.1, face: face(t, k.length, fc) }, { shadow: false });
  };
  // decoy approach: walks out of the fog from z 46 to 21 between "creak" and "wait"
  const decoyAt = (tt: number) => {
    const u = ss(W("creak", 5) - 0.5, W("wait", 2), tt);
    return { z: lerp(46, 21, u), walk: (tt - W("creak", 5)) * 0.55 * (u < 1 ? 1 : 0) };
  };
  const decoyOn = (eyes = 1) => {
    const d = decoyAt(t);
    S.decoy = { ...S.decoy, x: 0, z: d.z, walk: d.walk, eyes, visible: true };
  };

  switch (shot.id) {
    case 1: { // They locked him outside: the door slams in his face
      S.cabin.frontDoor = 1 - ss(0.28, SLAM1, t);
      const back = ss(SLAM1, SLAM1 + 0.3, t) * 0.35;
      const jump = Math.exp(-Math.max(0, t - SLAM1) * 9) * (t >= SLAM1 ? 1 : 0);
      add("noob", "noob", { x: -2.3, z: 4.75 + back, yaw: 0.25 - ss(SLAM1, SLAM1 + 0.25, t) * 0.4, headYaw: -ss(SLAM1, SLAM1 + 0.2, t) * 0.5, armL: 0.6 * (1 - ss(0.2, 0.6, t)) + jump * 1.2, armR: jump * 1.2, face: t < SLAM1 ? "smile" : "scared", squash: 1 - jump * 0.08, lean: back * 0.2 });
      add("red", "red", { x: -2.2, z: 2.4, yaw: 0, armR: 1.2 * (1 - ss(0.4, 0.7, t)), face: "angry" }, { shadow: false });
      S.cam = camKeys(t, t0, [{ t: 0, pos: [-1.2, 1.55, 9.6], look: [-2.3, 1.75, 4.2], fov: 44 }, { t: SLAM1, pos: [-1.5, 1.6, 8.4], look: [-2.3, 1.8, 4.4], fov: 36 }, { t: 1.4, pos: [-1.6, 1.65, 8.0], look: [-2.3, 1.85, 4.4], fov: 34 }], 0.04);
      break;
    }
    case 2: { // Then something knocked from inside
      let knock = 0;
      for (const k of KNOCKS) knock += Math.exp(-Math.max(0, t - k) * 18) * (t >= k ? 1 : 0);
      S.cabin.frontDoor = knock * 0.012;
      const back = 0.35 + ss(KNOCKS[0], KNOCKS[0] + 0.4, t) * 0.5;
      add("noob", "noob", { x: -1.1, z: 4.55 + back, yaw: Math.PI - 0.5 + ss(KNOCKS[0], KNOCKS[0] + 0.3, t) * 0.25, armL: 0.5, armR: 0.5 * ss(KNOCKS[0], KNOCKS[2], t), face: "scared", squash: 1 - knock * 0.04, lean: -0.08 });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [-3.4, 0.9, 8.6], look: [-1.5, 1.7, 4.4], fov: 42, roll: 0 }, { t: KNOCKS[0], pos: [-3.2, 0.85, 8.0], look: [-1.6, 1.75, 4.4], fov: 38, roll: 0.07 }], 0.06);
      break;
    }
    case 3: { // Night one on the Pinewood server: aerial over the clearing
      S.title = ss(t0 + 0.15, t0 + 0.6, t) * (1 - ss(shot.b / FPS - 0.45, shot.b / FPS, t));
      add("noob", "noob", { x: -2.0, z: 5.4, yaw: Math.PI - 0.3, face: "sad" });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [20, 15, 34], look: [0, 1.5, 4], fov: 44 }, { t: shot.b / FPS, pos: [13, 10.5, 25], look: [0, 1.5, 3], fov: 42 }], 0.02);
      break;
    }
    case 4: { // The pros built a cabin, and voted the new guy out (flashback inside)
      S.interior = 1;
      const vote = ss(W("night", 12), W("night", 12) + 0.35, t);
      const pros: [string, V3, number][] = [["red", [-0.6, 0, 0.6], -2.0], ["green", [0.7, 0, -0.4], -2.3], ["blue", [1.9, 0, 0.9], -1.9], ["purple", [-0.2, 0, -1.4], -2.4]];
      pros.forEach(([k, p, yaw], i) => add(k, k, { x: p[0], z: p[2], yaw, armR: vote * (2.6 + 0.2 * Math.sin(t * 6 + i)), face: face(t, i, k === "purple" ? "sly" : "angry") }, { shadow: false }));
      add("noob", "noob", { x: -2.4, z: 2.3, yaw: Math.PI * 0.78, face: vote > 0.5 ? "sad" : "neutral", armL: 0.2 }, { shadow: false });
      S.cabin.frontDoor = 1;
      S.cam = camKeys(t, t0, [{ t: t0, pos: [3.2, 2.5, 2.8], look: [-1.0, 1.5, 0.4], fov: 50 }, { t: shot.b / FPS, pos: [2.9, 2.3, 2.4], look: [-1.2, 1.6, 0.5], fov: 47 }], 0.04);
      break;
    }
    case 5: { // "No noobs. You'll get us caught." then slam
      S.cabin.frontDoor = 1 - ss(SLAM2 - 0.18, SLAM2, t);
      const point = ss(t0, t0 + 0.25, t) * (1 - ss(SLAM2 - 0.35, SLAM2 - 0.1, t));
      add("red", "red", { x: -2.3, z: 2.75 - ss(SLAM2 - 0.4, SLAM2 - 0.1, t) * 0.8, yaw: 0, armR: point * 1.45, face: face(t, 1, "shout") }, { shadow: false });
      add("green", "green", { x: -1.4, z: 1.6, yaw: -0.3, face: "angry" }, { shadow: false });
      add("noob", "noob", { x: -2.2, z: 4.7, yaw: Math.PI + 0.1, face: "sad" });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [1.9, 2.1, 8.8], look: [-2.3, 1.8, 3.0], fov: 38 }, { t: W("nonoobs", 2), pos: [1.5, 2.05, 8.2], look: [-2.3, 1.85, 3.0], fov: 34 }], 0.03);
      break;
    }
    case 6: { // waits by the gate with a starter lantern
      add("noob", "noob", { x: NOOB_CRATE[0], y: NOOB_CRATE[1], z: NOOB_CRATE[2], yaw: Math.PI - 0.55, sit: 1, armR: 0.4, armL: 0.35, headPitch: 0.15, face: face(t, 9, "sad"), lantern: 0.5 });
      S.lantern = { on: 0.6, pos: [NOOB_CRATE[0] - 0.55, 0.65, NOOB_CRATE[2] - 0.5] };
      S.cam = camKeys(t, t0, [{ t: t0, pos: [5.6, 1.5, 4.8], look: [2.4, 1.1, 9.8], fov: 40 }, { t: shot.b / FPS, pos: [4.6, 1.35, 5.8], look: [2.5, 1.0, 9.8], fov: 36 }], 0.03);
      break;
    }
    case 7: { // trees creak; something huge walks out of the fog
      S.sway = ss(W("creak", 2), W("creak", 5), t);
      decoyOn(ss(W("creak", 6), W("creak", 7), t));
      const up = ss(W("creak", 5), W("creak", 5) + 0.4, t);
      add("noob", "noob", { x: NOOB_CRATE[0] - 1.1 * up, y: NOOB_CRATE[1] * (1 - up), z: NOOB_CRATE[2], yaw: lerp(Math.PI - 0.55, 0.15, up), sit: 1 - up, armR: 0.5 + up * 0.5, headPitch: -0.12 * up, face: up > 0.3 ? "scared" : "sad", lantern: 0.6 });
      S.lantern = { on: 0.7, pos: [NOOB_CRATE[0] - 1.1 * up - 0.6, 1.0, NOOB_CRATE[2] + 0.3] };
      S.cam = camKeys(t, t0, [
        { t: t0, pos: [3.6, 1.5, 6.6], look: [0.4, 2.4, 24], fov: 44 },
        { t: W("creak", 7), pos: [3.3, 1.2, 7.0], look: [0.2, 3.6, 24], fov: 40, roll: 0.05 },
        { t: shot.b / FPS, pos: [3.1, 1.1, 7.3], look: [0.1, 3.9, 23], fov: 37, roll: 0.06 },
      ], 0.02);
      break;
    }
    case 8: { // Everyone inside presses against the window
      decoyOn();
      S.interior = 0.5;
      const press = ss(W("window", 1), W("window", 2), t);
      prosAtWindow("scared", 0.05 + press * 0.12);
      sitPurple("sly");
      S.cam = camKeys(t, t0, [{ t: t0, pos: [1.8, 2.15, 8.4], look: [1.7, 2.0, 3.4], fov: 36 }, { t: shot.b / FPS, pos: [1.75, 2.1, 7.0], look: [1.7, 2.0, 3.4], fov: 34 }], 0.03);
      break;
    }
    case 9: { // the moon is right behind it, and it casts no shadow
      decoyOn();
      add("noob", "noob", { x: 1.6, z: GATE_Z - 0.75, yaw: 0.1, armR: 0.9, face: "scared", lantern: 0.6 });
      S.lantern = { on: 0.6, pos: [1.0, 1.1, GATE_Z - 0.4] };
      S.cabin.frontDoor = 0;
      const down = ss(W("wait", 9), W("wait", 11), t);
      S.moonPatch = ss(W("wait", 2), W("wait", 5), t);
      S.cam = camKeys(t, t0, [
        { t: t0, pos: [6.2, 0.55, 13.5], look: [0.6, 5.2, 24], fov: 52, roll: -0.06 },
        { t: W("wait", 3), pos: [5.6, 0.6, 13.8], look: [0.4, 6.2, 24], fov: 50, roll: -0.06 },
      ], 0.015);
      // tilt down to the empty ground under its feet on "casts no shadow"
      S.cam.look = lv(S.cam.look, [0.2, 0.4, 19.5], down);
      S.cam.pos = lv(S.cam.pos, [4.4, 2.2, 14.5], down);
      S.cam.roll = lerp(S.cam.roll ?? 0, 0, down);
      break;
    }
    case 10: { // Noob looks back at the cabin
      decoyOn();
      const turn = ss(W("wall", 1), W("wall", 3), t);
      add("noob", "noob", { x: 1.6, z: GATE_Z - 0.75, yaw: lerp(0.1, Math.PI - 0.25, turn), headYaw: (1 - turn) * 0.0 + turn * -0.2, armR: 0.7, face: face(t, 9, turn > 0.6 ? "determined" : "scared"), lantern: 0.6 });
      S.lantern = { on: 0.6, pos: [1.6 + 0.6 * Math.cos(lerp(0.1, Math.PI, turn)), 1.1, GATE_Z - 0.75 + 0.5] };
      S.cam = camKeys(t, t0, [
        { t: t0, pos: [4.4, 1.9, 12.6], look: [1.5, 2.0, 9.6], fov: 38 },
        { t: W("wall", 4), pos: [3.6, 2.0, 12.9], look: [1.0, 2.2, 7.5], fov: 40 },
      ], 0.03);
      break;
    }
    case 11: { // on the wall, one player's shadow is moving on its own
      S.interior = 1;
      sitPurple("neutral");
      const move = ss(W("wall", 13), W("wall", 15), t);
      const tw = t - W("wall", 13);
      S.wallShadow = {
        x: STOOL[0], y: STOOL[1] + move * 0.15, z: STOOL[2], yaw: -Math.PI / 2 + 0.35 + move * 0.5, sit: 1 - move,
        armL: 0.5 + move * (2.4 + Math.sin(tw * 3) * 0.3), armR: 0.5 + move * (1.6 + Math.sin(tw * 3 + 1) * 0.4), armLz: move * 0.4,
        headYaw: move * 0.6, headPitch: move * -0.3, scale: 1 + move * 0.25,
      };
      S.cam = camKeys(t, t0, [{ t: t0, pos: [2.6, 2.2, 1.9], look: [-0.2, 1.9, -3.4], fov: 52 }, { t: shot.b / FPS, pos: [2.2, 2.1, 1.2], look: [-0.1, 2.0, -3.4], fov: 46 }], 0.03);
      break;
    }
    case 12: { // the thing outside was never the hunter: orbit reveals a flat cut-out on sticks
      decoyOn(0.6);
      const a = lerp(-0.25, 1.45, ss(t0, W("yousee", 8), t));
      const c: V3 = [0, 3.6, S.decoy.z];
      S.cam = { pos: [c[0] + Math.sin(a) * 8.5, 2.6, c[2] - Math.cos(a) * 8.5], look: c, fov: 46 };
      break;
    }
    case 13: { // bait, to keep everyone staring out the window: dollhouse cutaway
      decoyOn(0.6);
      S.interior = 1;
      S.cabin.roof = false;
      S.cabin.frontWall = false;
      prosAtWindow("scared", 0.15);
      sitPurple("sly", 0.5);
      const creep = ss(W("yousee", 12), W("yousee", 16), t);
      S.wallShadow = { x: STOOL[0] + creep * 1.6, y: STOOL[1], z: STOOL[2] + creep * 2.6, yaw: 0.3, sit: 0, armL: 1.3 + creep * 0.6, armR: 1.3 + creep * 0.6, scale: 1.25 };
      S.cam = camKeys(t, t0, [{ t: t0, pos: [7.5, 13, 11.5], look: [0, 0.5, 0.4], fov: 46 }, { t: shot.b / FPS, pos: [6.0, 11.4, 9.6], look: [0, 0.6, 0.2], fov: 44 }], 0.01);
      break;
    }
    case 14: { // The real one was already sitting by the fire
      S.interior = 1;
      const turn = ss(W("fire", 4), W("fire", 6), t);
      sitPurple(turn > 0.5 ? "sly" : "neutral", turn * 0.9);
      S.wallShadow = { x: STOOL[0], y: STOOL[1], z: STOOL[2], yaw: -Math.PI / 2 + 0.35, sit: 1, armL: 0.5, armR: 0.5, headYaw: turn * 0.9 };
      S.cam = camKeys(t, t0, [{ t: t0, pos: [1.1, 1.9, 1.8], look: [-2.4, 1.4, -1.4], fov: 40 }, { t: shot.b / FPS, pos: [0.4, 1.75, 1.0], look: [-2.4, 1.5, -1.4], fov: 34 }], 0.02);
      break;
    }
    case 15: { // He lifts his lantern and flashes it through the glass
      S.interior = 0.6;
      const p = walkPath([[1.6, 0, GATE_Z - 0.75], [1.9, 0, 4.7]], t, t0 + 0.05, 2.8);
      const lift = ss(W("lantern", 4), W("lantern", 6), t);
      const flash = Math.exp(-Math.max(0, t - LANTERN_FLASH) * 2.2) * (t >= LANTERN_FLASH ? 1 : 0);
      add("noob", "noob", { x: p.x, z: p.z, yaw: Math.PI, walk: p.walk, stride: p.moving ? 0.6 : 0, armR: lift * 2.6, face: face(t, 9, "determined"), lantern: 0.6 + flash * 3 });
      prosAtWindow(t > LANTERN_FLASH ? "scared" : "scared", 0.1 - ss(LANTERN_FLASH, LANTERN_FLASH + 0.3, t) * 0.25);
      S.lantern = { on: 0.6 + flash * 6, pos: [p.x + 0.3, 1.2 + lift * 1.3, p.z - 0.4] };
      S.flash = flash * 0.55;
      S.beam = ss(LANTERN_FLASH - 0.05, LANTERN_FLASH + 0.05, t);
      S.cam = camKeys(t, t0, [{ t: t0, pos: [6.6, 2.0, 9.8], look: [1.8, 1.8, 5.0], fov: 46 }, { t: W("lantern", 6), pos: [5.6, 2.2, 7.4], look: [1.8, 2.3, 4.4], fov: 40 }], 0.02);
      break;
    }
    case 16: { // the light hits the fake player, and its disguise flickers away
      S.interior = 1;
      S.beam = 1 - ss(W("reveal", 9), W("reveal", 10) + 0.3, t) * 0.6;
      const glitch = ss(W("reveal", 8), W("reveal", 10), t);
      const fl = (hash(Math.floor(t * 15)) < glitch ? 1 : 0) || (glitch >= 1 ? 1 : 0);
      const stand = ss(W("reveal", 1), W("reveal", 3), t);
      add("purple", fl ? "void" : "purple", { x: STOOL[0] - stand * 0.4, y: STOOL[1] * (1 - stand), z: STOOL[2], yaw: 0.7, sit: 1 - stand, armL: stand * 1.2, armR: stand * 1.4, armLz: stand * 0.3, face: fl ? "void" : "scared" }, { shadow: false, flicker: glitch > 0 && glitch < 1 ? 1 : 0 });
      for (const [k, p] of Object.entries(PRO_WIN)) add(k, k, { x: p[0] - 0.2, z: p[2] - 0.3, yaw: Math.PI + 0.6, face: "scared", armL: 0.4, armR: 0.4 }, { shadow: false });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [0.9, 1.75, 1.6], look: [-2.3, 1.5, -1.2], fov: 42, roll: 0.04 }, { t: shot.b / FPS, pos: [0.4, 1.65, 1.1], look: [-2.4, 1.6, -1.3], fov: 38, roll: 0.06 }], 0.03);
      break;
    }
    case 17: { // Noob kicks open the back door. Everybody out!
      S.interior = 1;
      S.cabin.backDoor = ss(KICK_DOOR, KICK_DOOR + 0.15, t);
      const inDoor = ss(KICK_DOOR - 0.3, KICK_DOOR, t);
      add("noob", "noob", { x: -1.3, z: -4.6 + inDoor * 0.5, yaw: 0, armR: 2.6, armL: 0.2, face: "shout", lantern: 1.4 }, { shadow: false });
      S.lantern = { on: 1.4, pos: [-1.0, 2.5, -3.9] };
      add("void", "void", { x: -3.3, z: -2.6, yaw: 0.9, armL: 1.9, armR: 1.6, lean: -0.25, face: "void", squash: 0.95 }, { shadow: false });
      const run = W("door", 6);
      const pros: [string, V3][] = [["red", [0.8, 0, 2.2]], ["green", [1.8, 0, 2.3]], ["blue", [2.7, 0, 2.1]]];
      pros.forEach(([k, p], i) => {
        const w = walkPath([p, [-0.6, 0, -1.8], [-1.0, 0, -5.5]], t, run + i * 0.18, 4.6);
        add(k, k, { x: w.x, z: w.z, yaw: w.moving ? w.yaw : Math.PI + 0.6, walk: w.walk, stride: w.moving ? 1 : 0, face: "scared" }, { shadow: false });
      });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [3.4, 2.6, -1.4], look: [-1.2, 1.4, -3.8], fov: 48 }, { t: shot.b / FPS, pos: [3.1, 2.5, -1.8], look: [-1.2, 1.5, -3.8], fov: 44 }], 0.03);
      break;
    }
    case 18: { // They sprint through the gate as the shadow melts in the sunrise
      S.dawn = ss(t0, W("escape", 11), t);
      S.gate = ss(t0, t0 + 0.4, t);
      const order = ["noob", "red", "green", "blue"];
      order.forEach((k, i) => {
        const w = walkPath([[-5.8, 0, -3.0], [-5.6, 0, 6.5], [0.0, 0, GATE_Z - 0.4], [0.4 - i * 0.9 + 1.4, 0, 16.0 + (i % 2) * 0.6]], t, t0 - 1.2 + i * 0.35, 6.0);
        add(k, k, { x: w.x, z: w.z, yaw: w.yaw, walk: w.walk, stride: w.moving ? 1 : 0, face: k === "noob" ? "determined" : "scared", lantern: k === "noob" ? 0.4 : 0 });
      });
      const melt = ss(W("escape", 8), W("escape", 11), t);
      add("void", "void", { x: -5.2, z: -2.2, yaw: 0.8, armL: 1.2, armR: 1.2, face: "void", squash: lerp(1, 0.02, melt), scale: 1 - melt * 0.2 }, { shadow: false });
      S.decoy = { ...S.decoy, visible: true, x: 0, z: 30, eyes: 0, collapse: ss(t0, t0 + 0.8, t) };
      S.cam = camKeys(t, t0, [{ t: t0, pos: [3.2, 2.0, 21.5], look: [-1.5, 1.4, 7.0], fov: 44 }, { t: shot.b / FPS, pos: [2.6, 1.8, 20.2], look: [-0.5, 1.4, 9.0], fov: 42 }], 0.02);
      break;
    }
    case 19: { // Welcome to the team, Noob.
      S.dawn = 1;
      S.gate = 1;
      S.decoy = { ...S.decoy, visible: false };
      const pat = ss(W("welcome", 0), W("welcome", 1), t) * (1 - ss(W("welcome", 4), W("welcome", 4) + 0.4, t));
      add("noob", "noob", { x: 0.4, z: 15.0, yaw: -0.25, face: face(t, 9, "grin"), armL: 0.2 });
      add("red", "red", { x: -0.85, z: 15.1, yaw: 0.9, armR: 1.3 * pat + 0.1, face: face(t, 1, "smile") });
      add("green", "green", { x: 1.6, z: 14.4, yaw: -0.7, armL: 2.7, armR: 2.7 * ss(W("welcome", 3), W("welcome", 4), t), face: face(t, 2, "grin") });
      add("blue", "blue", { x: -0.1, z: 13.7, yaw: 0.2, armL: 2.4, face: face(t, 3, "smile") });
      S.cam = camKeys(t, t0, [{ t: t0, pos: [0.9, 1.75, 19.6], look: [0.3, 1.55, 14.6], fov: 38 }, { t: shot.b / FPS, pos: [0.7, 1.75, 18.9], look: [0.3, 1.6, 14.6], fov: 36 }], 0.03);
      break;
    }
    case 20: { // He smiles. But on the grass behind him, there are two shadows.
      S.dawn = 1;
      S.gate = 1;
      S.decoy = { ...S.decoy, visible: false };
      add("noob", "noob", { x: 0.4, z: 15.0, yaw: 0.05, face: face(t, 9, "smile"), armL: 0.1 });
      add("red", "red", { x: -2.6, z: 14.2, yaw: 0.9, face: "smile" });
      add("green", "green", { x: -3.7, z: 15.2, yaw: 0.7, face: "smile" });
      add("blue", "blue", { x: -3.1, z: 13.4, yaw: 0.4, face: "smile" });
      const appear = ss(W("twist", 5), W("twist", 8), t);
      const reach = ss(W("twist", 10), W("twist", 12) + 0.4, t);
      S.ghostShadow = {
        pose: { x: -0.75, z: 14.1, yaw: 0.2, armL: 0.2 + reach * 1.0, armR: 0.25 + reach * 0.7, armRz: -reach * 0.3, headYaw: reach * -0.5, scale: 1.18 },
        opacity: appear,
      };
      S.cam = camKeys(t, t0, [
        { t: t0, pos: [0.5, 2.0, 18.0], look: [0.4, 2.05, 15.0], fov: 34 },
        { t: W("twist", 2), pos: [0.5, 2.0, 17.6], look: [0.4, 2.05, 15.0], fov: 34 },
        { t: W("twist", 6), pos: [0.8, 5.6, 20.0], look: [1.2, 0.3, 12.4], fov: 46 },
      ], 0.02);
      break;
    }
  }
  S.hook = shot.id <= 2 ? 1 : 0;
  // impact flip-shakes: sign flips every frame, decays over 7 frames
  let kick = 0;
  for (const [k, a] of KICKS) {
    const df = Math.round((t - k) * FPS);
    if (df >= 0 && df < 7) kick += a * (1 - df / 7) * (df % 2 ? -1 : 1);
  }
  if (kick) {
    S.cam = { ...S.cam, pos: [S.cam.pos[0] + kick * 0.05, S.cam.pos[1] + kick * 0.04, S.cam.pos[2]], roll: (S.cam.roll ?? 0) + kick * 0.012 };
  }
  // white flash after the hook
  const fl = f - FLASH_AT;
  if (fl >= 0 && fl < 5) S.flash = Math.max(S.flash, [0.9, 1, 0.7, 0.4, 0.15][fl]);
  return S;
}

// caption chunks: up to 3 words, broken at punctuation, timed to word starts
export type Chunk = { s: number; e: number; words: { w: string; s: number }[]; speaker: string };
export const CHUNKS: Chunk[] = (() => {
  const out: Chunk[] = [];
  for (const ln of lines.lines) {
    let cur: { w: string; s: number }[] = [];
    const flush = (end: number) => {
      if (cur.length) out.push({ s: cur[0].s - 0.05, e: end, words: cur, speaker: ln.speaker });
      cur = [];
    };
    ln.words.forEach((w, i) => {
      cur.push({ w: w.w, s: w.s });
      const next = ln.words[i + 1];
      if (!next) flush(ln.e + 0.18);
      else if (cur.length >= 3 || /[,.!?]$/.test(w.w)) flush(next.s - 0.05);
    });
  }
  return out;
})();
