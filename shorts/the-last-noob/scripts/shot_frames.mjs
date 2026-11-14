// prints shot ranges + a mid frame per shot (reads the same lines.json as story.ts)
import fs from "node:fs";
const l = JSON.parse(fs.readFileSync(new URL("../voice/lines.json", import.meta.url)));
const at = (id, i = 0) => Math.round((l.lines.find((x) => x.id === id).words[i].s - 2 / 30) * 30);
const B = [0, at("hook2"), at("night"), at("night", 6), at("nonoobs"), at("gate"), at("creak"), at("window"), at("wait"), at("wall"), at("wall", 6), at("yousee"), at("yousee", 9), at("fire"), at("lantern"), at("reveal"), at("door"), at("escape"), at("welcome"), at("twist"), Math.ceil(l.duration * 30)];
const mids = B.slice(0, -1).map((a, i) => Math.round((a + B[i + 1]) / 2));
console.log(JSON.stringify({ bounds: B, mids }));
