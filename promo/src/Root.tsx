import { Composition } from "remotion";
import { LaunchVideo } from "./Composition";

export const RemotionRoot = () => (
  <>
    <Composition
      id="LaunchSquare"
      component={LaunchVideo}
      durationInFrames={960}
      fps={30}
      width={1080}
      height={1080}
    />
    <Composition
      id="LaunchWide"
      component={LaunchVideo}
      durationInFrames={960}
      fps={30}
      width={1920}
      height={1080}
    />
  </>
);
