// Shared look for "The Last Noob": two-tone toon shading, near-black ink hulls, painted Canvas2D textures and the
// night / dawn light presets. Values follow the package's look targets (ink #0b0a0c, cool tint only in shade,
// fog = horizon colour, saturated lit colours) adapted to a moonlit forest.
import * as THREE from "three";

export const INK = "#0b0a0c";

// 3-step ramp: deep shade / shade / lit. Toon materials keep blocks flat and readable.
let ramp: THREE.DataTexture | null = null;
export function toonRamp(): THREE.DataTexture {
  if (ramp) return ramp;
  const d = new Uint8Array([70, 70, 70, 255, 150, 150, 150, 255, 255, 255, 255, 255]);
  ramp = new THREE.DataTexture(d, 3, 1, THREE.RGBAFormat);
  ramp.minFilter = ramp.magFilter = THREE.NearestFilter;
  ramp.needsUpdate = true;
  return ramp;
}

const matCache = new Map<string, THREE.Material>();
export function toon(color: string, opts: { map?: THREE.Texture; emissive?: string; emissiveIntensity?: number; key?: string } = {}) {
  const k = opts.key ?? `${color}|${opts.emissive ?? ""}|${opts.emissiveIntensity ?? 0}|${opts.map?.uuid ?? ""}`;
  let m = matCache.get(k) as THREE.MeshToonMaterial | undefined;
  if (!m) {
    m = new THREE.MeshToonMaterial({ color, gradientMap: toonRamp(), map: opts.map ?? null });
    if (opts.emissive) {
      m.emissive = new THREE.Color(opts.emissive);
      m.emissiveIntensity = opts.emissiveIntensity ?? 1;
    }
    matCache.set(k, m);
  }
  return m;
}

let inkMat: THREE.MeshBasicMaterial | null = null;
export function ink(): THREE.MeshBasicMaterial {
  if (!inkMat) inkMat = new THREE.MeshBasicMaterial({ color: INK, side: THREE.BackSide, fog: false });
  return inkMat;
}

export function glow(color: string, intensity = 1): THREE.MeshBasicMaterial {
  const k = `glow|${color}|${intensity}`;
  let m = matCache.get(k) as THREE.MeshBasicMaterial | undefined;
  if (!m) {
    m = new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), fog: false, toneMapped: false });
    matCache.set(k, m);
  }
  return m;
}

// ---------------------------------------------------------------- painted textures
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const texCache = new Map<string, THREE.CanvasTexture>();
function canvasTex(key: string, w: number, h: number, paint: (g: CanvasRenderingContext2D, r: () => number) => void, repeat?: [number, number]) {
  let t = texCache.get(key);
  if (t) return t;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const g = c.getContext("2d")!;
  paint(g, rng(key.length * 7919 + w));
  t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  if (repeat) {
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(...repeat);
  }
  texCache.set(key, t);
  return t;
}

// grass: blocky tiles with darker seams (seams painted in, as in the package's paint.ts)
export const grassTex = () =>
  canvasTex("grass", 512, 512, (g, r) => {
    const n = 8, s = 512 / n;
    for (let i = 0; i < n; i++)
      for (let j = 0; j < n; j++) {
        const v = 0.85 + r() * 0.3;
        g.fillStyle = `rgb(${Math.round(92 * v)},${Math.round(156 * v)},${Math.round(72 * v)})`;
        g.fillRect(i * s, j * s, s, s);
        for (let k = 0; k < 14; k++) {
          g.fillStyle = `rgba(${r() < 0.5 ? "60,120,50" : "130,190,90"},0.5)`;
          g.fillRect(i * s + r() * s, j * s + r() * s, 3 + r() * 5, 6 + r() * 10);
        }
      }
    g.strokeStyle = "rgba(25,50,25,0.55)";
    g.lineWidth = 3;
    for (let i = 0; i <= n; i++) {
      g.beginPath(); g.moveTo(i * s, 0); g.lineTo(i * s, 512); g.stroke();
      g.beginPath(); g.moveTo(0, i * s); g.lineTo(512, i * s); g.stroke();
    }
  }, [30, 30]);

export const dirtTex = () =>
  canvasTex("dirt", 256, 256, (g, r) => {
    g.fillStyle = "#9a7650"; g.fillRect(0, 0, 256, 256);
    for (let k = 0; k < 260; k++) {
      g.fillStyle = r() < 0.5 ? "rgba(120,90,60,0.6)" : "rgba(170,135,95,0.55)";
      g.fillRect(r() * 256, r() * 256, 4 + r() * 10, 4 + r() * 10);
    }
  }, [1, 6]);

// logs: horizontal planks with dark seams and knots
export const logTex = (tint = "#8a5a35") =>
  canvasTex("log" + tint, 256, 256, (g, r) => {
    const rows = 8, h = 256 / rows;
    const base = new THREE.Color(tint);
    for (let i = 0; i < rows; i++) {
      const v = 0.85 + r() * 0.25;
      g.fillStyle = `#${base.clone().multiplyScalar(v).getHexString()}`;
      g.fillRect(0, i * h, 256, h);
      g.fillStyle = "rgba(255,230,190,0.14)"; g.fillRect(0, i * h + 3, 256, 4);
      g.fillStyle = "rgba(30,15,8,0.7)"; g.fillRect(0, i * h + h - 4, 256, 4);
      for (let k = 0; k < 3; k++) {
        g.fillStyle = "rgba(60,30,15,0.5)";
        g.beginPath(); g.ellipse(r() * 256, i * h + h / 2, 6, 3, 0, 0, Math.PI * 2); g.fill();
      }
    }
  }, [1, 1]);

export const plankTex = () =>
  canvasTex("plank", 256, 256, (g, r) => {
    const cols = 6, w = 256 / cols;
    for (let i = 0; i < cols; i++) {
      const v = 0.85 + r() * 0.25;
      g.fillStyle = `rgb(${Math.round(150 * v)},${Math.round(104 * v)},${Math.round(64 * v)})`;
      g.fillRect(i * w, 0, w, 256);
      g.fillStyle = "rgba(25,12,6,0.75)"; g.fillRect(i * w + w - 3, 0, 3, 256);
      g.fillRect(i * w, r() * 256, w, 3);
    }
  }, [3, 3]);

export const stoneTex = () =>
  canvasTex("stone", 256, 256, (g, r) => {
    g.fillStyle = "#3a3634"; g.fillRect(0, 0, 256, 256);
    const rows = 6, h = 256 / rows;
    for (let i = 0; i < rows; i++) {
      let x = (i % 2) * -20;
      while (x < 256) {
        const w = 34 + r() * 30, v = 0.8 + r() * 0.35;
        g.fillStyle = `rgb(${Math.round(128 * v)},${Math.round(122 * v)},${Math.round(116 * v)})`;
        g.fillRect(x + 2, i * h + 2, w - 4, h - 4);
        x += w;
      }
    }
  }, [1, 1]);

export const roofTex = () =>
  canvasTex("roof", 256, 256, (g, r) => {
    const rows = 8, h = 256 / rows;
    for (let i = 0; i < rows; i++) {
      for (let x = (i % 2) * -16; x < 256; x += 32) {
        const v = 0.8 + r() * 0.3;
        g.fillStyle = `rgb(${Math.round(120 * v)},${Math.round(52 * v)},${Math.round(44 * v)})`;
        g.fillRect(x + 1, i * h + 1, 30, h - 2);
      }
      g.fillStyle = "rgba(20,8,6,0.8)"; g.fillRect(0, i * h + h - 3, 256, 3);
    }
  }, [3, 2]);

// ---------------------------------------------------------------- light presets
export type Light = "night" | "dawn";
export const LOOK = {
  night: {
    skyTop: "#0b1233", skyHorizon: "#2c3d73", fog: "#24305e", fogNear: 18, fogFar: 78,
    hemiSky: "#6f82c9", hemiGround: "#1a1c2c", hemi: 1.15,
    moon: "#cfe0ff", moonI: 1.6, ambient: 0.25,
  },
  dawn: {
    skyTop: "#5d7fc4", skyHorizon: "#ffc48a", fog: "#e9b38f", fogNear: 25, fogFar: 110,
    hemiSky: "#ffe1bf", hemiGround: "#5b4a52", hemi: 1.35,
    moon: "#ffcf9e", moonI: 2.2, ambient: 0.35,
  },
} as const;
