// Sets for "The Last Noob": a fenced clearing in a block-pine forest, a log cabin with a lit interior (fireplace on
// the left wall, the back wall where the impostor's shadow plays), the yard gate, sky dome, moon, stars and the
// flat cardboard decoy "creature". Everything is boxes + painted canvas textures, recoloured per light.
import React, { useMemo } from "react";
import * as THREE from "three";
import { Block } from "./Block";
import { dirtTex, glow, grassTex, ink, logTex, LOOK, plankTex, roofTex, stoneTex, toon, type Light } from "./look";

// cabin layout (metres). Front wall faces +z (yard, gate, forest, moon).
export const CABIN = {
  W: 9, D: 7, H: 4.2, T: 0.3,
  frontDoor: [-3.0, -1.6] as [number, number], doorH: 2.9,
  window: [0.2, 3.2] as [number, number], winY: [1.3, 2.9] as [number, number],
  backDoor: [-2.0, -0.6] as [number, number],
  fire: [-4.05, 0.9, -0.7] as [number, number, number],
};
export const GATE_Z = 10.5;
export const MOON_POS: [number, number, number] = [6, 44, 135];
export const SUN_POS: [number, number, number] = [-60, 38, 85];

// ---------------------------------------------------------------- sky
export const Sky: React.FC<{ dawn: number }> = ({ dawn }) => {
  const mat = useMemo(
    () =>
      new THREE.ShaderMaterial({
        side: THREE.BackSide, depthWrite: false, fog: false,
        uniforms: {
          uTopN: { value: new THREE.Color(LOOK.night.skyTop) }, uHorN: { value: new THREE.Color(LOOK.night.skyHorizon) },
          uTopD: { value: new THREE.Color(LOOK.dawn.skyTop) }, uHorD: { value: new THREE.Color(LOOK.dawn.skyHorizon) },
          uDawn: { value: 0 }, uSun: { value: new THREE.Vector3(...SUN_POS).normalize() },
        },
        vertexShader: `varying vec3 vD; void main(){ vD = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.0);} `,
        fragmentShader: `
          uniform vec3 uTopN,uHorN,uTopD,uHorD,uSun; uniform float uDawn; varying vec3 vD;
          float h(vec3 p){ return fract(sin(dot(p, vec3(12.9898,78.233,45.164)))*43758.5453); }
          void main(){
            float y = clamp(vD.y, 0.0, 1.0);
            vec3 n = mix(uHorN, uTopN, pow(y, 0.55));
            vec3 d = mix(uHorD, uTopD, pow(y, 0.7));
            float sun = pow(max(dot(vD, uSun), 0.0), 18.0);
            d += vec3(1.0, 0.55, 0.25) * sun * 0.6;
            vec3 c = mix(n, d, uDawn);
            // stars: hashed cells, fade out at dawn
            vec3 q = floor(vD * 260.0);
            float s = step(0.9965, h(q)) * smoothstep(0.08, 0.35, vD.y) * (1.0 - uDawn);
            c += vec3(0.85, 0.9, 1.0) * s;
            gl_FragColor = vec4(c, 1.0);
          }`,
      }),
    [],
  );
  mat.uniforms.uDawn.value = dawn;
  return (
    <mesh material={mat} renderOrder={-10}>
      <sphereGeometry args={[320, 32, 16]} />
    </mesh>
  );
};

export const Moon: React.FC<{ dawn: number }> = ({ dawn }) => (
  <group position={MOON_POS} visible={dawn < 0.95}>
    <mesh>
      <circleGeometry args={[5, 48]} />
      <meshBasicMaterial color={new THREE.Color("#f3f6ff").multiplyScalar(1.4)} fog={false} toneMapped={false} transparent opacity={1 - dawn} side={THREE.DoubleSide} />
    </mesh>
    <mesh position={[0, 0, -0.5]}>
      <circleGeometry args={[13, 48]} />
      <meshBasicMaterial color="#9fb6ff" fog={false} transparent opacity={0.16 * (1 - dawn)} depthWrite={false} side={THREE.DoubleSide} />
    </mesh>
    {/* lookAt the clearing so the disc faces the camera rig */}
  </group>
);

// ---------------------------------------------------------------- ground + path
export const Ground: React.FC = () => (
  <group>
    <mesh rotation={[-Math.PI / 2, 0, 0]} material={toon("#ffffff", { map: grassTex() })}>
      <planeGeometry args={[400, 400]} />
    </mesh>
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[-1.5, 0.006, 7]} material={toon("#ffffff", { map: dirtTex() })}>
      <planeGeometry args={[2.2, 8]} />
    </mesh>
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.006, 16]} material={toon("#ffffff", { map: dirtTex() })}>
      <planeGeometry args={[2.6, 12]} />
    </mesh>
  </group>
);

// ---------------------------------------------------------------- forest (instanced block pines + ink hulls)
function rng(seed: number) {
  let s = seed;
  return () => ((s = (s * 16807) % 2147483647) - 1) / 2147483646;
}
type Tree = { x: number; z: number; s: number; r: number; ph: number };
export const TREES: Tree[] = (() => {
  const r = rng(12345), out: Tree[] = [];
  while (out.length < 170) {
    const x = (r() - 0.5) * 130, z = (r() - 0.5) * 130 + 8;
    const dc = Math.hypot(x, z - 3);
    if (dc < 17) continue; // clearing
    if (Math.abs(x) < 3.5 && z > 15 && z < 40) continue; // the creature's lane
    out.push({ x, z, s: 0.8 + r() * 0.6, r: r() * Math.PI, ph: r() * 6.28 });
  }
  return out;
})();

const TIERS = [
  { y: 2.2, w: 4.2, h: 1.6, c: "#1f6b45" },
  { y: 3.7, w: 3.2, h: 1.5, c: "#25804f" },
  { y: 5.1, w: 2.1, h: 1.4, c: "#2c9158" },
  { y: 6.2, w: 1.0, h: 0.9, c: "#33a062" },
];
export const Forest: React.FC<{ sway: number; t: number; shadow?: THREE.Material }> = ({ sway, t, shadow }) => {
  const parts = useMemo(() => {
    const list: { geo: THREE.BoxGeometry; hull: THREE.BoxGeometry; mat: THREE.Material; y: number; tier: number }[] = [
      { geo: new THREE.BoxGeometry(0.7, 2.2, 0.7), hull: new THREE.BoxGeometry(0.76, 2.26, 0.76), mat: toon("#5b3a22"), y: 1.1, tier: -1 },
    ];
    TIERS.forEach((ti, i) =>
      list.push({ geo: new THREE.BoxGeometry(ti.w, ti.h, ti.w), hull: new THREE.BoxGeometry(ti.w + 0.09, ti.h + 0.09, ti.w + 0.09), mat: toon(ti.c), y: ti.y, tier: i }),
    );
    return list.map((p) => {
      const m = new THREE.InstancedMesh(p.geo, p.mat, TREES.length);
      const h = new THREE.InstancedMesh(p.hull, ink(), TREES.length);
      const sh = new THREE.InstancedMesh(p.geo, p.mat, TREES.length);
      sh.frustumCulled = m.frustumCulled = h.frustumCulled = false;
      return { ...p, m, h, sh };
    });
  }, []);
  const tmp = useMemo(() => new THREE.Object3D(), []);
  for (const p of parts) {
    TREES.forEach((tr, i) => {
      const lean = sway * (0.035 + 0.02 * Math.max(0, p.tier)) * Math.sin(t * 2.3 + tr.ph);
      // rotate around the trunk base: offset x by height * lean
      const y = p.y * tr.s;
      tmp.position.set(tr.x + Math.sin(lean) * y, y, tr.z);
      tmp.rotation.set(0, tr.r, lean);
      tmp.scale.setScalar(tr.s);
      tmp.updateMatrix();
      p.m.setMatrixAt(i, tmp.matrix);
      p.h.setMatrixAt(i, tmp.matrix);
      p.sh.setMatrixAt(i, tmp.matrix);
    });
    p.m.instanceMatrix.needsUpdate = true;
    p.h.instanceMatrix.needsUpdate = true;
    p.sh.instanceMatrix.needsUpdate = true;
    if (shadow) p.sh.material = shadow;
    p.sh.visible = !!shadow;
  }
  return (
    <group>
      {parts.map((p, i) => (
        <group key={i}>
          <primitive object={p.m} />
          <primitive object={p.h} />
          <primitive object={p.sh} />
        </group>
      ))}
    </group>
  );
};

// ---------------------------------------------------------------- cabin
// a wall along x (front/back) with rectangular holes, built from boxes
function wallX(z: number, holes: { x: [number, number]; y: [number, number] }[], W: number, H: number, T: number, map: THREE.Texture) {
  const out: React.ReactElement[] = [];
  const xs = [-W / 2, ...holes.flatMap((h) => h.x), W / 2];
  let k = 0;
  for (let i = 0; i < xs.length - 1; i++) {
    const a = xs[i], b = xs[i + 1];
    if (b - a < 1e-3) continue;
    const hole = holes.find((h) => Math.abs(h.x[0] - a) < 1e-6 && Math.abs(h.x[1] - b) < 1e-6);
    const segs: [number, number][] = hole ? [[0, hole.y[0]], [hole.y[1], H]] : [[0, H]];
    for (const [y0, y1] of segs) {
      if (y1 - y0 < 1e-3) continue;
      out.push(<Block key={`w${z}${k++}`} size={[b - a, y1 - y0, T]} position={[(a + b) / 2, (y0 + y1) / 2, z]} material={toon("#ffffff", { map })} />);
    }
  }
  return out;
}

export type CabinState = { frontDoor: number; backDoor: number; roof: boolean; fire: number; t: number; frontWall?: boolean };
export const Cabin: React.FC<CabinState> = ({ frontDoor, backDoor, roof, fire, t, frontWall = true }) => {
  const C = CABIN;
  const log = logTex("#8d5a33"), logIn = logTex("#a8703f");
  const flick = 0.85 + 0.15 * Math.sin(t * 17) * Math.sin(t * 7.3 + 1);
  return (
    <group>
      {/* floor */}
      <Block size={[C.W, 0.2, C.D]} position={[0, 0.1, 0]} material={toon("#ffffff", { map: plankTex() })} />
      {/* front wall (z+) with door + window */}
      <group visible={frontWall}>
        {wallX(C.D / 2, [{ x: C.frontDoor, y: [0, C.doorH] }, { x: C.window, y: C.winY }], C.W, C.H, C.T, log)}
        {/* window frame + glass + mullion */}
        <Block size={[C.window[1] - C.window[0] + 0.2, 0.14, C.T + 0.16]} position={[(C.window[0] + C.window[1]) / 2, C.winY[0] - 0.05, C.D / 2]} color="#5b3a22" />
        <Block size={[0.1, C.winY[1] - C.winY[0], 0.12]} position={[(C.window[0] + C.window[1]) / 2, (C.winY[0] + C.winY[1]) / 2, C.D / 2]} color="#5b3a22" />
        <mesh position={[(C.window[0] + C.window[1]) / 2, (C.winY[0] + C.winY[1]) / 2, C.D / 2 + 0.02]}>
          <planeGeometry args={[C.window[1] - C.window[0], C.winY[1] - C.winY[0]]} />
          <meshBasicMaterial color="#ffd9a0" transparent opacity={0.12} depthWrite={false} />
        </mesh>
      </group>
      {/* front door, hinged at its left edge, opens inward */}
      <group position={[C.frontDoor[0], 0.2, C.D / 2]} rotation={[0, frontDoor * 1.7, 0]}>
        <Block size={[C.frontDoor[1] - C.frontDoor[0], C.doorH - 0.2, 0.14]} position={[(C.frontDoor[1] - C.frontDoor[0]) / 2, (C.doorH - 0.2) / 2, 0]} material={toon("#ffffff", { map: plankTex() })}>
          <Block size={[0.1, 0.1, 0.1]} position={[0.5, 0, 0.1]} color="#e2b64a" />
        </Block>
      </group>
      {/* back wall (z-) with back door; inner face lighter logs so the shadow reads */}
      {wallX(-C.D / 2, [{ x: C.backDoor, y: [0, C.doorH] }], C.W, C.H, C.T, logIn)}
      <group position={[C.backDoor[0], 0.2, -C.D / 2]} rotation={[0, -backDoor * 1.75, 0]}>
        <Block size={[C.backDoor[1] - C.backDoor[0], C.doorH - 0.2, 0.14]} position={[(C.backDoor[1] - C.backDoor[0]) / 2, (C.doorH - 0.2) / 2, 0]} material={toon("#ffffff", { map: plankTex() })} />
      </group>
      {/* side walls */}
      {[-1, 1].map((s) => (
        <Block key={s} size={[C.T, C.H, C.D + C.T]} position={[s * C.W / 2, C.H / 2, 0]} material={toon("#ffffff", { map: s < 0 ? logIn : log })} />
      ))}
      {/* corner posts */}
      {[[-1, -1], [-1, 1], [1, -1], [1, 1]].map(([a, b], i) => (
        <Block key={i} size={[0.5, C.H + 0.1, 0.5]} position={[a * C.W / 2, (C.H + 0.1) / 2, b * C.D / 2]} color="#5b3a22" />
      ))}
      {/* roof (gable along x) */}
      <group visible={roof}>
        {[-1, 1].map((s) => (
          <Block key={s} size={[C.W + 1.2, 0.3, C.D / 2 / Math.cos(0.55) + 0.7]} position={[0, C.H + 1.0, s * C.D / 4 * 1.05]} rotation={[s * 0.55, 0, 0]} material={toon("#ffffff", { map: roofTex() })} />
        ))}
        <Block size={[0.3, 1.9, C.D * 0.82]} position={[-C.W / 2 + 0.15, C.H + 0.75, 0]} material={toon("#ffffff", { map: log })} />
        <Block size={[0.3, 1.9, C.D * 0.82]} position={[C.W / 2 - 0.15, C.H + 0.75, 0]} material={toon("#ffffff", { map: log })} />
        <Block size={[1.0, 2.4, 1.0]} position={[-3.6, C.H + 1.4, -0.7]} material={toon("#ffffff", { map: stoneTex() })} />
      </group>
      {/* fireplace on the left wall */}
      <group position={[C.fire[0], 0, C.fire[2]]}>
        <Block size={[0.7, 1.7, 2.0]} position={[0.2, 0.85, 0]} material={toon("#ffffff", { map: stoneTex() })} />
        <Block size={[0.5, 2.6, 1.3]} position={[0, 2.9, 0]} material={toon("#ffffff", { map: stoneTex() })} />
        <Block size={[0.5, 0.75, 1.1]} position={[0.36, 0.62, 0]} color="#16110f" noInk />
        {[0, 1, 2].map((i) => (
          <Block key={i} size={[0.28, (0.3 + 0.12 * Math.sin(t * 9 + i * 2)) * fire, 0.28]} position={[0.42, 0.4 + 0.15 * fire, -0.3 + i * 0.3]}
            material={glow(i === 1 ? "#ffd36b" : "#ff7a2e", 1.6 * flick)} noInk visible={fire > 0.05} />
        ))}
      </group>
      {/* furniture: table, stools, bunk, crate, rug */}
      <Block size={[2.0, 0.12, 1.1]} position={[1.4, 1.0, -1.6]} color="#7a4c2a" />
      {[[0.55, -2.05], [2.25, -2.05], [0.55, -1.15], [2.25, -1.15]].map(([x, z], i) => (
        <Block key={i} size={[0.12, 0.95, 0.12]} position={[x, 0.5, z]} color="#5b3a22" />
      ))}
      <Block size={[0.6, 0.55, 0.6]} position={[-2.25, 0.47, -1.2]} color="#6b4428" />
      <Block size={[2.6, 0.02, 1.8]} position={[-1.6, 0.21, 0.3]} color="#a33b3b" noInk />
      <Block size={[1.4, 0.7, 2.6]} position={[3.6, 0.55, -1.8]} color="#6b4428">
        <Block size={[1.3, 0.2, 2.4]} position={[0, 0.42, 0]} color="#e8e1d2" />
      </Block>
      <Block size={[0.8, 0.8, 0.8]} position={[3.7, 0.6, 1.9]} material={toon("#ffffff", { map: plankTex() })} />
      {/* hanging lamp */}
      <Block size={[0.3, 0.3, 0.3]} position={[0.5, C.H - 0.6, 0]} material={glow("#ffcf7a", 1.4)} noInk />
    </group>
  );
};

// ---------------------------------------------------------------- yard fence + gate
export const Fence: React.FC<{ open: number }> = ({ open }) => {
  const posts: number[] = [];
  for (let x = -13; x <= 13.01; x += 1.75) if (Math.abs(x) > 1.8) posts.push(x);
  return (
    <group position={[0, 0, GATE_Z]}>
      {posts.map((x) => (
        <Block key={x} size={[0.28, 1.5, 0.28]} position={[x, 0.75, 0]} color="#7a5232" />
      ))}
      {[-1, 1].map((s) => (
        <group key={s}>
          {[0.55, 1.15].map((y) => (
            <Block key={y} size={[11.4, 0.16, 0.12]} position={[s * 7.4, y, 0.05]} color="#9a6a3e" />
          ))}
          <Block size={[0.42, 2.2, 0.42]} position={[s * 1.75, 1.1, 0]} color="#5b3a22" />
        </group>
      ))}
      <Block size={[4.0, 0.3, 0.3]} position={[0, 2.35, 0]} color="#5b3a22" />
      {/* gate panels hinged at the big posts, swing out (+z) */}
      {[-1, 1].map((s) => (
        <group key={s} position={[s * 1.55, 0, 0.05]} rotation={[0, s * open * 1.4, 0]}>
          {[0.45, 1.05, 1.55].map((y) => (
            <Block key={y} size={[1.45, 0.16, 0.1]} position={[-s * 0.75, y, 0]} color="#a87443" />
          ))}
          <Block size={[0.12, 1.4, 0.1]} position={[-s * 1.35, 1.0, 0]} color="#a87443" />
          <Block size={[1.7, 0.12, 0.08]} position={[-s * 0.75, 1.0, 0.02]} rotation={[0, 0, s * 0.42]} color="#8a5a33" />
        </group>
      ))}
      <Block size={[0.55, 0.45, 0.55]} position={[2.7, 0.23, -0.7]} material={toon("#ffffff", { map: plankTex() })} />
    </group>
  );
};

// ---------------------------------------------------------------- the decoy: a flat cut-out on sticks (casts no shadow)
export const Decoy: React.FC<{ x: number; z: number; walk: number; eyes: number; yaw?: number; collapse?: number }> = ({ x, z, walk, eyes, yaw = 0, collapse = 0 }) => {
  const sw = Math.sin(walk * Math.PI * 2);
  const D = 0.06, dark = "#141221";
  return (
    <group position={[x, 0, z]} rotation={[-collapse * 1.4, yaw + sw * 0.05, sw * 0.03]}>
      {/* two thin support sticks: the giveaway from the side */}
      <Block size={[0.08, 6.2, 0.08]} position={[-0.3, 3.1, -0.25]} color="#7a5232" />
      <Block size={[0.08, 6.2, 0.08]} position={[0.3, 3.1, -0.25]} color="#7a5232" />
      <Block size={[1.4, 0.08, 0.08]} position={[0, 4.4, -0.2]} color="#7a5232" />
      {/* cut-out body */}
      {[-1, 1].map((s) => (
        <Block key={s} size={[0.42, 3.0, D]} position={[s * 0.4, 1.5, 0]} rotation={[0, 0, s * sw * 0.08]} color={dark} />
      ))}
      <Block size={[1.5, 2.4, D]} position={[0, 4.1, 0]} color={dark} />
      {[-1, 1].map((s) => (
        <Block key={s} size={[0.32, 3.4, D]} position={[s * 1.0, 3.6, 0]} rotation={[0, 0, s * (0.12 + sw * 0.06)]} color={dark} />
      ))}
      <Block size={[1.15, 1.1, D]} position={[0, 5.9, 0]} color={dark} />
      {[-1, 1].map((s) => (
        <mesh key={s} position={[s * 0.27, 6.0, D / 2 + 0.01]} material={glow("#f4f8ff", 1.2 + eyes * 1.5)}>
          <planeGeometry args={[0.28, 0.16]} />
        </mesh>
      ))}
    </group>
  );
};
