// Original block-style characters: box torso / limbs / head, a painted face on the head's front, one accessory each.
// Posed per frame from the story (walk cycle with planted bob, arm raises, sit, head turns, expressions).
import React from "react";
import * as THREE from "three";
import { Block, ShadowContext } from "./Block";
import { glow, toon } from "./look";

export type Face = "neutral" | "smile" | "grin" | "scared" | "angry" | "sly" | "void" | "shout" | "determined" | "sad";
export type Hat = "none" | "helmet" | "cap" | "hood" | "ponytail" | "tuft";
export type Outfit = { skin: string; shirt: string; pants: string; hat: Hat; accent: string; badge?: boolean };

export const CAST: Record<string, Outfit> = {
  noob: { skin: "#f4c99a", shirt: "#ff9f2e", pants: "#4f6075", hat: "tuft", accent: "#6b3f1f" },
  red: { skin: "#e8b48a", shirt: "#c8313a", pants: "#2d2f3a", hat: "helmet", accent: "#9aa3ad" },
  green: { skin: "#c98f62", shirt: "#2f9e5b", pants: "#3a3150", hat: "ponytail", accent: "#2b1a12" },
  blue: { skin: "#f0c7a5", shirt: "#2f6fd6", pants: "#2b3348", hat: "cap", accent: "#f2d240" },
  purple: { skin: "#e9c09a", shirt: "#7b3fc4", pants: "#2a2438", hat: "hood", accent: "#5a2c95" },
  void: { skin: "#120f1c", shirt: "#120f1c", pants: "#0c0a14", hat: "hood", accent: "#0c0a14" },
};

export type Pose = {
  x: number; z: number; y?: number; yaw?: number;
  walk?: number; stride?: number; // walk phase in cycles, stride 0..1 (1 = run)
  armL?: number; armR?: number; armLz?: number; armRz?: number; // radians, forward raise / sideways spread
  headYaw?: number; headPitch?: number; lean?: number; sit?: number; face?: Face;
  squash?: number; scale?: number; lantern?: number; // lantern: 0 none, >0 = light amount
};

// ---------------------------------------------------------------- faces (Canvas2D, cached)
const faceCache = new Map<string, THREE.CanvasTexture>();
function faceTex(face: Face, skin: string) {
  const k = face + skin;
  let t = faceCache.get(k);
  if (t) return t;
  const c = document.createElement("canvas");
  c.width = c.height = 256;
  const g = c.getContext("2d")!;
  g.fillStyle = skin;
  g.fillRect(0, 0, 256, 256);
  const ink = "#1b1220";
  g.fillStyle = ink;
  g.strokeStyle = ink;
  g.lineCap = "round";
  g.lineWidth = 14;
  const eye = (x: number, y: number, w = 26, h = 44) => g.fillRect(x - w / 2, y - h / 2, w, h);
  const brow = (x: number, y: number, tilt: number) => {
    g.beginPath(); g.moveTo(x - 26, y - tilt); g.lineTo(x + 26, y + tilt); g.stroke();
  };
  const arc = (y: number, r: number, a0: number, a1: number) => { g.beginPath(); g.arc(128, y, r, a0, a1); g.stroke(); };
  if (face === "void") {
    g.fillStyle = "#120f1c"; g.fillRect(0, 0, 256, 256);
    g.fillStyle = "#e9f4ff";
    eye(86, 112, 40, 22); eye(170, 112, 40, 22);
  } else {
    const ey = face === "scared" ? 104 : 110;
    if (face === "scared") { eye(86, ey, 30, 54); eye(170, ey, 30, 54); }
    else if (face === "sly") { eye(86, ey + 8, 34, 18); eye(170, ey + 8, 34, 18); }
    else { eye(86, ey); eye(170, ey); }
    if (face === "angry" || face === "determined") { brow(86, 66, 10); brow(170, 66, -10); }
    if (face === "scared") { brow(86, 52, -8); brow(170, 52, 8); }
    if (face === "smile") arc(150, 46, 0.25 * Math.PI, 0.75 * Math.PI);
    if (face === "sad") { arc(222, 40, 1.25 * Math.PI, 1.75 * Math.PI); brow(86, 62, -7); brow(170, 62, 7); }
    if (face === "neutral") { g.beginPath(); g.moveTo(104, 190); g.lineTo(152, 190); g.stroke(); }
    if (face === "grin") { g.beginPath(); g.moveTo(78, 170); g.quadraticCurveTo(128, 236, 178, 170); g.closePath(); g.fill(); }
    if (face === "scared" || face === "shout") { g.beginPath(); g.ellipse(128, 194, face === "shout" ? 30 : 18, face === "shout" ? 26 : 22, 0, 0, Math.PI * 2); g.fill(); }
    if (face === "angry") { g.beginPath(); g.moveTo(98, 196); g.quadraticCurveTo(128, 176, 158, 196); g.stroke(); }
    if (face === "sly") { g.beginPath(); g.moveTo(92, 182); g.quadraticCurveTo(140, 206, 176, 168); g.stroke(); }
    if (face === "determined") { g.beginPath(); g.moveTo(100, 190); g.lineTo(156, 186); g.stroke(); }
  }
  t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  faceCache.set(k, t);
  return t;
}

const headMats = new Map<string, THREE.Material[]>();
function headMaterial(o: Outfit, face: Face) {
  const k = face + o.skin;
  let m = headMats.get(k);
  if (!m) {
    const s = toon(o.skin);
    const f = face === "void"
      ? new THREE.MeshBasicMaterial({ map: faceTex(face, o.skin), toneMapped: false })
      : new THREE.MeshToonMaterial({ map: faceTex(face, o.skin), gradientMap: (s as THREE.MeshToonMaterial).gradientMap });
    m = [s, s, s, s, f, s];
    headMats.set(k, m);
  }
  return m;
}

// ---------------------------------------------------------------- rig
const LEG = 0.9, TORSO = 0.9, TW = 0.9, TD = 0.45, LW = 0.44, HEAD = 0.6;

export const Blocky: React.FC<{ who: keyof typeof CAST | Outfit; pose: Pose; flicker?: number }> = ({ who, pose: p, flicker = 0 }) => {
  const shadow = React.useContext(ShadowContext);
  const o = typeof who === "string" ? CAST[who] : who;
  const walk = (p.walk ?? 0) * Math.PI * 2;
  const stride = p.stride ?? 0;
  const swing = Math.sin(walk) * (0.35 + 0.55 * stride) * Math.min(1, stride * 3);
  const sit = p.sit ?? 0;
  const bob = Math.abs(Math.sin(walk)) * 0.06 * Math.min(1, stride * 3);
  const hipY = LEG * (1 - 0.45 * sit) + bob * 0 + (stride > 0 ? 0.05 - bob : 0);
  const sq = p.squash ?? 1;
  const face = p.face ?? "neutral";
  const hm = shadow ? undefined : headMaterial(o, face);
  return (
    <group position={[p.x, p.y ?? 0, p.z]} rotation={[0, p.yaw ?? 0, 0]} scale={[(p.scale ?? 1) / Math.sqrt(sq), (p.scale ?? 1) * sq, (p.scale ?? 1) / Math.sqrt(sq)]}>
      <group position={[0, hipY, 0]} rotation={[p.lean ?? 0, 0, 0]}>
        {/* legs */}
        {[-1, 1].map((s) => (
          <group key={s} position={[s * LW / 2 * 1.02, 0, 0]} rotation={[sit * -1.45 + s * swing, 0, 0]}>
            <Block size={[LW, LEG, TD]} position={[0, -LEG / 2, 0]} color={o.pants} />
            <Block size={[LW + 0.02, 0.16, TD + 0.08]} position={[0, -LEG + 0.08, 0.04]} color="#262028" />
          </group>
        ))}
        {/* torso */}
        <Block size={[TW, TORSO, TD]} position={[0, TORSO / 2, 0]} color={o.shirt}>
          {o.hat === "tuft" && !shadow && <Block size={[0.3, 0.3, 0.02]} position={[0.2, 0.18, TD / 2 + 0.01]} color="#fff4d6" noInk />}
          <Block size={[TW + 0.03, 0.12, TD + 0.03]} position={[0, -TORSO / 2 + 0.06, 0]} color={o.accent} noInk />
        </Block>
        {/* arms */}
        {[-1, 1].map((s) => {
          const raise = s < 0 ? p.armL ?? 0 : p.armR ?? 0;
          const spread = s < 0 ? p.armLz ?? 0 : p.armRz ?? 0;
          return (
            <group key={s} position={[s * (TW / 2 + LW / 2), TORSO - 0.08, 0]} rotation={[-raise - s * swing * 0.9 * (raise === 0 ? 1 : 0.2), 0, s * (0.04 + spread)]}>
              <Block size={[LW, TORSO, TD]} position={[0, -TORSO / 2 + 0.08, 0]} color={o.shirt}>
                <Block size={[LW - 0.02, 0.22, TD - 0.02]} position={[0, -TORSO / 2 + 0.11, 0]} color={o.skin} noInk />
              </Block>
              {s > 0 && (p.lantern ?? 0) > 0 && <Lantern amount={p.lantern!} />}
            </group>
          );
        })}
        {/* head */}
        <group position={[0, TORSO + 0.02, 0]} rotation={[p.headPitch ?? 0, p.headYaw ?? 0, 0]}>
          <Block size={[HEAD + 0.06, HEAD, HEAD]} position={[0, HEAD / 2, 0]} material={hm} color={o.skin} />
          <Hat o={o} />
        </group>
      </group>
      {flicker > 0 && !shadow && <FlickerAura amount={flicker} />}
    </group>
  );
};

const Hat: React.FC<{ o: Outfit }> = ({ o }) => {
  const H = HEAD;
  switch (o.hat) {
    case "helmet":
      return (
        <group>
          <Block size={[H + 0.16, 0.26, H + 0.14]} position={[0, H + 0.02, 0]} color={o.accent} />
          <Block size={[0.1, 0.18, H + 0.2]} position={[0, H + 0.22, 0]} color="#c8313a" />
        </group>
      );
    case "cap":
      return (
        <group>
          <Block size={[H + 0.1, 0.18, H + 0.1]} position={[0, H + 0.04, 0]} color={o.shirt} />
          <Block size={[H + 0.04, 0.06, 0.3]} position={[0, H - 0.02, H / 2 + 0.14]} color={o.accent} />
        </group>
      );
    case "hood":
      return (
        <group>
          <Block size={[H + 0.16, 0.14, H + 0.12]} position={[0, H + 0.05, -0.02]} color={o.accent} />
          <Block size={[0.1, H + 0.04, H + 0.12]} position={[-H / 2 - 0.08, H / 2 + 0.02, -0.02]} color={o.accent} />
          <Block size={[0.1, H + 0.04, H + 0.12]} position={[H / 2 + 0.08, H / 2 + 0.02, -0.02]} color={o.accent} />
          <Block size={[H + 0.16, H + 0.04, 0.1]} position={[0, H / 2 + 0.02, -H / 2 - 0.07]} color={o.accent} />
        </group>
      );
    case "ponytail":
      return (
        <group>
          <Block size={[H + 0.1, 0.16, H + 0.1]} position={[0, H + 0.02, -0.02]} color={o.accent} />
          <Block size={[H + 0.1, 0.14, 0.06]} position={[0, H - 0.08, H / 2 + 0.02]} color="#f2d240" noInk />
          <Block size={[0.24, 0.5, 0.22]} position={[0, H - 0.25, -H / 2 - 0.12]} color={o.accent} />
        </group>
      );
    case "tuft":
      return <Block size={[0.18, 0.16, 0.18]} position={[0.08, H + 0.08, 0.06]} rotation={[0, 0, 0.3]} color={o.accent} />;
    default:
      return null;
  }
};

// Starter lantern hanging from the right hand; its glow is the story's light source.
const Lantern: React.FC<{ amount: number }> = ({ amount }) => (
  <group position={[0, -TORSO + 0.05, 0.12]}>
    <Block size={[0.04, 0.16, 0.04]} position={[0, -0.05, 0]} color="#2a2a2a" noShadow />
    <Block size={[0.26, 0.04, 0.26]} position={[0, -0.15, 0]} color="#3b3b3b" />
    <Block size={[0.2, 0.26, 0.2]} position={[0, -0.3, 0]} material={glow("#ffc35a", 1.2 + amount * 1.6)} />
    <Block size={[0.28, 0.05, 0.28]} position={[0, -0.45, 0]} color="#3b3b3b" />
  </group>
);

// Glitch shell shown while the disguise "flickers away": offset translucent copies, purely graphic, no gore.
const FlickerAura: React.FC<{ amount: number }> = ({ amount }) => (
  <group>
    {[0, 1, 2].map((i) => (
      <mesh key={i} position={[Math.sin(i * 2.1 + amount * 40) * 0.12 * amount, 1.2 + i * 0.25, 0]}>
        <boxGeometry args={[1.5, 0.08, 0.7]} />
        <meshBasicMaterial color={i % 2 ? "#9a6bff" : "#e9f4ff"} transparent opacity={0.6 * amount} toneMapped={false} />
      </mesh>
    ))}
  </group>
);

export const HEIGHT = LEG + TORSO + HEAD;
