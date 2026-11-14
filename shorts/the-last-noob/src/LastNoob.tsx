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
      <pointLight position={[0.5, 3.4, 0.2]} color="#ffd9b0" intensity={14 * (1 - d * 0.7)} distance={8} decay={1.6} />
      <pointLight position={[CABIN.fire[0] + 0.7, 1.1, CABIN.fire[2]]} color="#ff9a4a" intensity={13 * flick * (1 - d * 0.7)} distance={9} decay={1.6} />
      {exterior && <pointLight position={[1.7, 1.9, 5.0]} color="#ffbe72" intensity={7 * (1 - d)} distance={9} decay={1.6} />}
      {s.lantern && <pointLight position={s.lantern.pos} color="#ffc35a" intensity={6 * s.lantern.on} distance={8 + s.lantern.on * 2} decay={1.6} />}

      <Sky dawn={d} />
      <Moon dawn={d} />
      <Ground />
      <Forest sway={s.sway} t={s.t} shadow={gMat} />
      <Cabin {...s.cabin} t={s.t} />
      <Fence open={s.gate} />
      {d < 0.05 && <LaneProps />}
      {s.moonPatch > 0 && (
        // pale moonlit ground in the decoy's lane: the props' shadows cross it, the decoy's feet have none
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.008, 19.8]} renderOrder={-1}>
          <circleGeometry args={[4.2, 40]} />
          <meshBasicMaterial color="#b9c9ff" transparent opacity={0.32 * s.moonPatch} depthWrite={false} blending={THREE.AdditiveBlending} />
        </mesh>
      )}
      <ShadowContext.Provider value={gMat}>
        <Fence open={s.gate} />
        {d < 0.05 && <LaneProps />}
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

const Captions: React.FC<{ t: number; scale: number; hook: boolean }> = ({ t, scale, hook }) => {
  const c = CHUNKS.find((k) => t >= k.s && t < k.e);
  if (!c) return null;
  const u = Math.min(1, (t - c.s) / 0.12);
  const pop = 1 + 0.14 * Math.sin(u * Math.PI) * (1 - u * 0.5) - 0.1 * (1 - u);
  const size = (hook ? 118 : 96) * scale;
  return (
    <div style={{ position: "absolute", left: 0, right: 0, top: hook ? "52%" : "60%", display: "flex", justifyContent: "center", padding: `0 ${90 * scale}px` }}>
      <div style={{
        fontFamily: FONT, fontSize: size, lineHeight: 1.04, textAlign: "center", color: "#fff",
        WebkitTextStroke: `${(hook ? 18 : 15) * scale}px #0b0a0c`, paintOrder: "stroke fill", letterSpacing: 1.5 * scale,
        textShadow: `0 ${8 * scale}px 0 rgba(0,0,0,0.55), 0 0 ${30 * scale}px rgba(0,0,0,0.5)`, transform: `scale(${pop})`, textTransform: "uppercase",
      }}>
        {c.words.map((w, i) => {
          const active = t >= w.s && (i === c.words.length - 1 || t < c.words[i + 1].s);
          return (
            <span key={i} style={{ color: active ? (c.speaker === "pro" ? "#ff8f80" : hook ? "#ff5a4e" : "#ffd84a") : "#ffffff" }}>
              {w.w.replace(/[,.]$/, "")}{i < c.words.length - 1 ? " " : ""}
            </span>
          );
        })}
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
      {/* grade: split tone (cool sky, warm ground light), vignette, red pulse on the hook knocks */}
      <AbsoluteFill style={{ mixBlendMode: "soft-light", background: s.dawn > 0.5
        ? "linear-gradient(180deg, rgba(120,150,255,0.35) 0%, rgba(255,190,120,0.45) 100%)"
        : "linear-gradient(180deg, rgba(40,80,200,0.55) 0%, rgba(255,160,80,0.30) 100%)" }} />
      <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 50%, rgba(${s.hook ? "70,0,10" : s.dawn > 0.5 ? "60,20,10" : "5,8,30"},${s.hook ? 0.7 : 0.55}) 100%)` }} />
      {/* letterbox-safe top shade so the title / sky stays deep */}
      <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,10,0.35) 0%, rgba(0,0,0,0) 22%)" }} />
      {s.flash > 0 && <AbsoluteFill style={{ background: s.shot === 15 ? "#fff3cf" : "#fff", opacity: s.flash }} />}
      <Title a={s.title} scale={scale} />
      {props.captions !== false && <Captions t={frame / 30} scale={scale} hook={s.hook > 0} />}
      {props.audio !== false && <Audio src={staticFile("audio/mix.wav")} />}
    </AbsoluteFill>
  );
};
