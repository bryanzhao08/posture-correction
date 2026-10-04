import React from "react";
import { Composition } from "remotion";
import { Promo } from "./Promo";

export const Root: React.FC = () => (
  <Composition id="FormCoachPromo" component={Promo} durationInFrames={1800} fps={30} width={1920} height={1080} />
);
