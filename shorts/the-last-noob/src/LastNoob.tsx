// The Last Noob: They Left the Noob Outside. Composition: three.js scene (ThreeCanvas) driven by story.stateAt(frame),
// plus the HTML layers on top: grade/vignette, white flashes, title card and word-timed English captions.
import React, { useMemo } from "react";
import * as THREE from "three";
import { AbsoluteFill, Audio, getInputProps, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import { Block, ShadowContext, shadowMaterial, type ShadowSpec } from "./Block";
import { Blocky } from "./Blocky";
import { LOOK } from "./look";
import { CHUNKS, stateAt, TOTAL, type Cam, type State } from "./story";
import { CABIN, Cabin, Decoy, Fence, Forest, Ground, MOON_POS, Moon, Sky, SUN_POS } from "./World";

export const LAST_NOOB_FRAMES = TOTAL;

const mixC = (a: string, b: string, u: number) => new THREE.Color(a).lerp(new THREE.Color(b), u);
const neg = (p: number[]): [number, number, number] => [-p[0], -p[1], -p[2]];

// vertical frames are narrow: story fovs are authored tight, widened here once for every shot
const FOV_K = 1.4;
const CameraRig: React.FC<{ cam: Cam }> = ({ cam }) => {
  const { camera } = useThree();
  const c = camera as THREE.PerspectiveCamera;
  c.position.set(...cam.pos);
  c.up.set(0, 1, 0);
  c.lookAt(...cam.look);
  if (cam.roll) c.rotateZ(cam.roll);
  c.fov = cam.fov * FOV_K;
  c.near = 0.1;
  c.far = 700;
  c.updateProjectionMatrix();
  return null;
};

const Renderer: React.FC = () => {
  const { gl, scene } = useThree();
  gl.toneMapping = THREE.NeutralToneMapping;
  gl.toneMappingExposure = 1.0;
  scene.background = null;
  return null;
};

// lane props that DO cast moon shadows, so the decoy's missing shadow reads
const LaneProps: React.FC = () => (
  <group>
    <Block size={[1.0, 0.7, 0.9]} position={[-2.6, 0.35, 19.6]} color="#6d6a72" />
    <Block size={[0.7, 0.9, 0.7]} position={[2.9, 0.45, 20.4]} color="#5b3a22" />
    <Block size={[0.5, 0.35, 0.6]} position={[-1.7, 0.18, 22.6]} color="#7d7a82" />
    <Block size={[0.3, 1.2, 0.3]} position={[1.9, 0.6, 17.5]} color="#7a5232" />
    <Block size={[1.0, 0.2, 0.2]} position={[1.9, 1.05, 17.5]} color="#a87443" />
  </group>
);

const Beam: React.FC<{ amount: number }> = ({ amount }) => {
  const geo = useMemo(() => {
    const g = new THREE.CylinderGeometry(0.25, 1.6, 1, 24, 1, true);
    g.translate(0, -0.5, 0);
    g.rotateX(-Math.PI / 2); // tip at origin, opens toward -z
    return g;
  }, []);
  const from = new THREE.Vector3(1.9, 2.4, 4.0), to = new THREE.Vector3(-2.3, 1.4, -1.2);
  const len = from.distanceTo(to);
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 0, -1), to.clone().sub(from).normalize());
  if (amount <= 0.01) return null;
  return (
    <mesh geometry={geo} position={from} quaternion={q} scale={[1, 1, len]}>
      <meshBasicMaterial color="#ffe2a0" transparent opacity={0.22 * amount} blending={THREE.AdditiveBlending} depthWrite={false} side={THREE.DoubleSide} fog={false} />
    </mesh>
  );
};

const Scene: React.FC<{ s: State }> = ({ s }) => {
  const d = s.dawn;
  const N = LOOK.night, D = LOOK.dawn;
  const keyPos = d < 0.5 ? MOON_POS : SUN_POS;
  const shadowDir = neg(keyPos);
  const opacity = lerp(0.78, 0.6, d) * (d > 0.35 && d < 0.65 ? Math.abs(d - 0.5) / 0.15 : 1);
  const ground: ShadowSpec = { dir: shadowDir, n: [0, 1, 0], d: 0, opacity, color: d < 0.5 ? "#04061a" : "#3a1f2e" };
  const gMat = shadowMaterial(ground);
  const fog = mixC(N.fog, D.fog, d);
  const flick = 0.82 + 0.18 * Math.sin(s.t * 13) * Math.sin(s.t * 5.1 + 2);
  const exterior = s.interior < 1;
  return (
    <>
      <Renderer />
      <CameraRig cam={s.cam} />
      <fog attach="fog" args={[fog, lerp(N.fogNear, D.fogNear, d), lerp(N.fogFar, D.fogFar, d)]} />
      <hemisphereLight args={[mixC(N.hemiSky, D.hemiSky, d), mixC(N.hemiGround, D.hemiGround, d), lerp(N.hemi, D.hemi, d)]} />
      <ambientLight intensity={lerp(N.ambient, D.ambient, d)} />
      <directionalLight position={keyPos} color={d < 0.5 ? N.moon : D.moon} intensity={d < 0.5 ? lerp(N.moonI, 0.4, d * 2) : lerp(0.4, D.moonI, (d - 0.5) * 2)} />
      {/* interior: warm ceiling lamp + fire (stays on all night) */}
      <pointLight position={[0.5, 3.4, 0.2]} color="#ffc27a" intensity={22 * (1 - d * 0.7)} distance={8} decay={1.6} />
      <pointLight position={[CABIN.fire[0] + 0.7, 1.1, CABIN.fire[2]]} color="#ff9a4a" intensity={16 * flick * (1 - d * 0.7)} distance={9} decay={1.6} />
      {exterior && <pointLight position={[1.7, 1.9, 5.0]} color="#ffbe72" intensity={7 * (1 - d)} distance={9} decay={1.6} />}
      {s.lantern && <pointLight position={s.lantern.pos} color="#ffc35a" intensity={6 * s.lantern.on} distance={8 + s.lantern.on * 2} decay={1.6} />}

      <Sky dawn={d} />
      <Moon dawn={d} />
      <Ground />
      <Forest sway={s.sway} t={s.t} shadow={gMat} />
      <Cabin {...s.cabin} t={s.t} />
      <Fence open={s.gate} />
      <LaneProps />
      <ShadowContext.Provider value={gMat}>
        <Fence open={s.gate} />
        <LaneProps />
      </ShadowContext.Provider>
      {/* character shadows: the rig flattened onto the ground along the key light (opaque tint, no overlap darkening) */}
      <ShadowContext.Provider value={groundShadowMat(d, 1)}>
        <group matrix={flatten(shadowDir)} matrixAutoUpdate={false}>
          {s.actors.filter((a) => a.shadow).map((a) => <Blocky key={a.key} who={a.who as never} pose={a.pose} />)}
        </group>
      </ShadowContext.Provider>
      {s.decoy.visible && <Decoy {...s.decoy} />}
      {s.actors.map((a) => <Blocky key={a.key} who={a.who as never} pose={a.pose} flicker={a.flicker} />)}
      {s.wallShadow && (
        // the impostor's shadow, flattened onto the back wall's inner face and posed on its own
        <ShadowContext.Provider value={WALL_SHADOW}>
          <group position={[s.wallShadow.x + 3.2, 0.45, -CABIN.D / 2 + CABIN.T / 2 + 0.03]} scale={[1.1, 1.1, 0.01]}>
            <Blocky who="void" pose={{ ...s.wallShadow, x: 0, z: 0, yaw: (s.wallShadow.yaw ?? 0) + 0.2 }} />
          </group>
        </ShadowContext.Provider>
      )}
      {s.ghostShadow && s.ghostShadow.opacity > 0.01 && (
        <ShadowContext.Provider value={groundShadowMat(d, s.ghostShadow.opacity)}>
          <group matrix={flatten(shadowDir, 0.024)} matrixAutoUpdate={false}>
            <Blocky who="void" pose={s.ghostShadow.pose} />
          </group>
        </ShadowContext.Provider>
      )}
      <Beam amount={s.beam} />
    </>
  );
};

const lerp = (a: number, b: number, u: number) => a + (b - a) * u;
// projection onto y = h along light direction l: x' = x - lx/ly * y, z' = z - lz/ly * y
const flatten = (l: [number, number, number], h = 0.018) =>
  new THREE.Matrix4().set(1, -l[0] / l[1], 0, 0, 0, 0, 0, h, 0, -l[2] / l[1], 1, 0, 0, 0, 0, 1);
const gsCache = new Map<string, THREE.Material>();
// shadow tint over grass: night blue-black, dawn violet (fades in for the ghost)
function groundShadowMat(dawn: number, a: number) {
  const k = `${dawn > 0.5 ? 1 : 0}|${a.toFixed(2)}`;
  let m = gsCache.get(k);
  if (!m) {
    m = new THREE.MeshBasicMaterial({ color: dawn > 0.5 ? "#2a2a3e" : "#060814", transparent: true, opacity: (dawn > 0.5 ? 0.62 : 0.72) * a, depthWrite: false,
      side: THREE.DoubleSide });
    gsCache.set(k, m);
  }
  return m;
}
const WALL_SHADOW = new THREE.MeshBasicMaterial({ color: "#140a0c", transparent: true, opacity: 0.72, depthWrite: false, fog: false });

// ---------------------------------------------------------------- HTML layers
const FONT = "LilitaOne";
const fontCss = `@font-face { font-family: '${FONT}'; src: url('${staticFile("fonts/LilitaOne-Regular.ttf")}') format('truetype'); }`;

// captions: lower-middle (inside the 9:16 safe area, clear of the bottom UI band), 2-3 words, active word lit,
// a speaker tag for the pros' dialogue, bigger red-accented hook words
const Captions: React.FC<{ t: number; scale: number }> = ({ t, scale }) => {
  const c = CHUNKS.find((k) => t >= k.s && t < k.e);
  if (!c) return null;
  const pop = Math.min(1, (t - c.s) / 0.1);
  const hook = c.s < 3.2;
  const size = (hook ? 112 : 86) * scale;
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: `${hook ? 57 : 61}%`, display: "flex", flexDirection: "column", alignItems: "center", padding: `0 ${90 * scale}px` }}>
      {c.speaker === "pro" && (
        <div style={{ fontFamily: FONT, fontSize: 40 * scale, color: "#fff", background: "#c8313a", borderRadius: 14 * scale, padding: `${4 * scale}px ${18 * scale}px`, marginBottom: 10 * scale, border: `${4 * scale}px solid #0b0a0c`, letterSpacing: 2 * scale }}>THE PROS</div>
      )}
      <div style={{
        fontFamily: FONT, fontSize: size, lineHeight: 1.04, textAlign: "center", color: "#fff", maxWidth: 900 * scale,
        WebkitTextStroke: `${(hook ? 16 : 13) * scale}px #0b0a0c`, paintOrder: "stroke fill", letterSpacing: 1.5 * scale,
        textShadow: `0 ${7 * scale}px 0 rgba(0,0,0,0.55)`, transform: `translateY(${(1 - pop) * 18 * scale}px) scale(${0.86 + 0.14 * pop})`, opacity: 0.4 + 0.6 * pop, textTransform: "uppercase",
      }}>
        {c.words.map((w, i) => {
          const active = t >= w.s && (i === c.words.length - 1 || t < c.words[i + 1].s);
          const hot = hook && /inside|outside/i.test(w.w);
          const col = active ? (hot ? "#ff5a3c" : c.speaker === "pro" ? "#ff9b8f" : "#ffd84a") : hot ? "#ff8a6a" : "#ffffff";
          return (
            <span key={i} style={{ color: col, display: "inline-block", marginRight: i < c.words.length - 1 ? size * 0.26 : 0, transform: active ? "scale(1.06)" : undefined }}>
              {w.w.replace(/[,.]$/, "")}
            </span>
          );
        })}
      </div>
    </div>
  );
};

// small game-style HUD chip (top centre, inside the safe area)
const Hud: React.FC<{ s: State; scale: number }> = ({ s, scale }) => {
  if (s.shot < 4 || s.shot > 19) return null;
  const day = s.dawn > 0.5;
  return (
    <div style={{ position: "absolute", top: 120 * scale, left: 0, right: 0, display: "flex", justifyContent: "center" }}>
      <div style={{ fontFamily: FONT, fontSize: 38 * scale, color: day ? "#3b2410" : "#e9f0ff", background: day ? "rgba(255,214,140,0.9)" : "rgba(12,16,40,0.72)",
        border: `${4 * scale}px solid ${day ? "#3b2410" : "#8fa6ff"}`, borderRadius: 40 * scale, padding: `${6 * scale}px ${26 * scale}px`, letterSpacing: 3 * scale, display: "flex", alignItems: "center", gap: 12 * scale }}>
        <span style={{ width: 24 * scale, height: 24 * scale, borderRadius: "50%", background: day ? "#ff9d2e" : "#dfe8ff", boxShadow: day ? "none" : `inset ${-7 * scale}px 0 0 #6f82c9`, display: "inline-block" }} />
        {day ? "SUNRISE  SURVIVED" : s.shot >= 15 ? "NIGHT 1  ESCAPE!" : "NIGHT 1  LOCKED OUT"}
      </div>
    </div>
  );
};

const Title: React.FC<{ a: number; scale: number }> = ({ a, scale }) =>
  a <= 0 ? null : (
    <div style={{ position: "absolute", top: 230 * scale, left: 0, right: 0, textAlign: "center", opacity: a, transform: `translateY(${(1 - a) * -30 * scale}px)` }}>
      <div style={{ fontFamily: FONT, fontSize: 132 * scale, color: "#ffd84a", WebkitTextStroke: `${16 * scale}px #0b0a0c`, paintOrder: "stroke fill", lineHeight: 1 }}>THE LAST NOOB</div>
      <div style={{ fontFamily: FONT, fontSize: 58 * scale, color: "#fff", WebkitTextStroke: `${10 * scale}px #0b0a0c`, paintOrder: "stroke fill", marginTop: 14 * scale }}>They Left the Noob Outside</div>
    </div>
  );

export const LastNoob: React.FC = () => {
  const { width, height, fps } = useVideoConfig();
  const frame = Math.min(TOTAL - 1, useCurrentFrame() * (30 / fps)); // story frames are 30 fps
  const s = stateAt(frame);
  const scale = height / 1920;
  const props = getInputProps() as { audio?: boolean; captions?: boolean };
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <style>{fontCss}</style>
      <ThreeCanvas width={width} height={height} gl={{ antialias: getInputProps().aa !== false, stencil: true }} dpr={1}>
        <Scene s={s} />
      </ThreeCanvas>
      {/* grade: soft-light colour wash (teal night / peach dawn), vignette, red pulse on the knocks */}
      <AbsoluteFill style={{ background: s.dawn > 0.5 ? "linear-gradient(180deg, rgba(255,170,110,0.35), rgba(255,120,150,0.18))" : "linear-gradient(180deg, rgba(40,70,160,0.32), rgba(20,120,140,0.22))", mixBlendMode: "soft-light", opacity: s.interior >= 1 ? 0.45 : 1 }} />
      <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 52%, rgba(${s.dawn > 0.5 ? "60,20,10" : "4,6,24"},0.62) 100%)` }} />
      {s.alarm > 0.02 && <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 50%, rgba(0,0,0,0) 40%, rgba(200,20,20,0.55) 100%)", opacity: Math.min(1, s.alarm) }} />}
      <Hud s={s} scale={scale} />
      {s.flash > 0 && <AbsoluteFill style={{ background: s.shot === 15 ? "#fff3cf" : "#fff", opacity: s.flash }} />}
      <Title a={s.title} scale={scale} />
      {props.captions !== false && <Captions t={frame / 30} scale={scale} />}
      {props.audio !== false && <Audio src={staticFile("audio/mix.wav")} />}
    </AbsoluteFill>
  );
};
