// Block primitives: a toon-shaded box with a back-face ink hull, plus the planar projected shadow material that lets
// the story decide who casts a shadow (the decoy casts none, the impostor's wall shadow moves on its own).
import React, { createContext, useContext, useMemo } from "react";
import * as THREE from "three";
import { ink, toon } from "./look";

// ---------------------------------------------------------------- planar shadows
// Projects every vertex along a light direction onto a plane. Stencil keeps overlapping parts from double-darkening.
const shadowMats = new Map<string, THREE.ShaderMaterial>();
export type ShadowSpec = { dir: [number, number, number]; n: [number, number, number]; d: number; color?: string; opacity?: number; ref?: number };
export function shadowMaterial(s: ShadowSpec) {
  const k = JSON.stringify(s);
  let m = shadowMats.get(k);
  if (m) return m;
  const dir = new THREE.Vector3(...s.dir).normalize();
  m = new THREE.ShaderMaterial({
    uniforms: {
      uDir: { value: dir }, uN: { value: new THREE.Vector3(...s.n).normalize() }, uD: { value: s.d },
      uColor: { value: new THREE.Color(s.color ?? "#05060e") }, uOpacity: { value: s.opacity ?? 0.55 },
    },
    vertexShader: /* glsl */ `
      uniform vec3 uDir; uniform vec3 uN; uniform float uD;
      void main() {
        vec4 lp = vec4(position, 1.0);
        #ifdef USE_INSTANCING
          lp = instanceMatrix * lp;
        #endif
        vec4 wp = modelMatrix * lp;
        float t = (uD - dot(uN, wp.xyz)) / dot(uN, uDir);
        vec3 p = wp.xyz + uDir * max(t, 0.0) + uN * 0.012;
        gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor; uniform float uOpacity;
      void main() { gl_FragColor = vec4(uColor, uOpacity); }`,
    transparent: true,
    side: THREE.DoubleSide,
    depthWrite: false,
    stencilWrite: true,
    stencilRef: s.ref ?? 1,
    stencilFunc: THREE.NotEqualStencilFunc,
    stencilZPass: THREE.ReplaceStencilOp,
    polygonOffset: true,
    polygonOffsetFactor: -2,
  });
  shadowMats.set(k, m);
  return m;
}

// When a ShadowContext material is set, every Block below renders with it (no ink, no colour): a shadow pass.
export const ShadowContext = createContext<THREE.Material | null>(null);

const boxCache = new Map<string, THREE.BoxGeometry>();
export function boxGeo(w: number, h: number, d: number) {
  const k = `${w.toFixed(3)}|${h.toFixed(3)}|${d.toFixed(3)}`;
  let g = boxCache.get(k);
  if (!g) boxCache.set(k, (g = new THREE.BoxGeometry(w, h, d)));
  return g;
}

type V3 = [number, number, number];
export const Block: React.FC<{
  size: V3; position?: V3; rotation?: V3; color?: string; material?: THREE.Material | THREE.Material[];
  map?: THREE.Texture; inkW?: number; noInk?: boolean; visible?: boolean; noShadow?: boolean; children?: React.ReactNode;
}> = ({ size, position, rotation, color = "#ffffff", material, map, inkW = 0.045, noInk, visible = true, noShadow, children }) => {
  const shadow = useContext(ShadowContext);
  const geo = boxGeo(...size);
  const hull = useMemo(() => boxGeo(size[0] + inkW, size[1] + inkW, size[2] + inkW), [size[0], size[1], size[2], inkW]);
  if (shadow && noShadow) return null;
  const mat = shadow ?? material ?? toon(color, { map });
  return (
    <group position={position} rotation={rotation} visible={visible}>
      <mesh geometry={geo} material={mat} />
      {!shadow && !noInk && <mesh geometry={hull} material={ink()} />}
      {children}
    </group>
  );
};
