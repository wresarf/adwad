import React from "react";
import { Composition } from "remotion";
import { LastNoob, LAST_NOOB_FRAMES } from "./LastNoob";

// 1080x1920 vertical, 30 fps. Render a 2K master with --scale 1.3333 (1440x2560) if the machine allows.
// LastNoob15: the same 30 fps timeline sampled every other frame (fast preview renders on CPU-only machines).
export const Root: React.FC = () => (
  <>
    <Composition id="LastNoob" component={LastNoob} durationInFrames={LAST_NOOB_FRAMES} fps={30} width={1080} height={1920} />
    <Composition id="LastNoob15" component={LastNoob} durationInFrames={Math.ceil(LAST_NOOB_FRAMES / 2)} fps={15} width={1080} height={1920} />
  </>
);
