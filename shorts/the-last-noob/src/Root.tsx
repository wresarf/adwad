import React from "react";
import { Composition } from "remotion";
import { LastNoob, LAST_NOOB_FRAMES } from "./LastNoob";

// 1080x1920 vertical, 30 fps. Render a 2K master with --scale 1.3333 (1440x2560) if the machine allows.
export const Root: React.FC = () => (
  <Composition id="LastNoob" component={LastNoob} durationInFrames={LAST_NOOB_FRAMES} fps={30} width={1080} height={1920} />
);
