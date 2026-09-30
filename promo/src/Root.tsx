import { Composition } from "remotion";
import { LaunchVideo, ShortLaunchVideo } from "./Composition";

export const RemotionRoot = () => (
  <>
    <Composition
      id="LaunchSquare"
      component={ShortLaunchVideo}
      durationInFrames={450}
      fps={30}
      width={1080}
      height={1080}
    />
    <Composition
      id="LaunchWide"
      component={ShortLaunchVideo}
      durationInFrames={450}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="LaunchFullSquare"
      component={LaunchVideo}
      durationInFrames={960}
      fps={30}
      width={1080}
      height={1080}
    />
    <Composition
      id="LaunchFullWide"
      component={LaunchVideo}
      durationInFrames={960}
      fps={30}
      width={1920}
      height={1080}
    />
  </>
);
