import React from "react";
import {
  AbsoluteFill,
  Img,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

const paper = "#f4f2ec",
  ink = "#20201f",
  purple = "#6751cf",
  orange = "#f4aa7c";
const icons = ["linear", "t3", "cursor", "zed", "chatgpt", "figma"];
const names = ["Linear", "T3 Code", "Cursor", "Zed", "ChatGPT", "Figma"];
const font =
  '-apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif';
const enter = (frame: number, delay = 0) =>
  spring({
    frame: frame - delay,
    fps: 30,
    config: { damping: 24, stiffness: 110 },
  });
const Icon: React.FC<{ slug: string; original?: boolean; size: number }> = ({
  slug,
  original = false,
  size,
}) => (
  <Img
    src={staticFile(`icons/${slug}-${original ? "original" : "preview"}.png`)}
    style={{ width: size, height: size, objectFit: "contain" }}
  />
);
const Head: React.FC<{
  children: React.ReactNode;
  top?: number;
  width?: number;
  size?: number;
}> = ({ children, top = 155, width = 920, size = 74 }) => (
  <div
    style={{
      position: "absolute",
      top,
      left: 80,
      width,
      fontSize: size,
      fontWeight: 750,
      lineHeight: 1.08,
      letterSpacing: -3,
    }}
  >
    {children}
  </div>
);
const Note: React.FC<{
  children: React.ReactNode;
  top: number;
  width?: number;
}> = ({ children, top, width = 910 }) => (
  <div
    style={{
      position: "absolute",
      top,
      left: 85,
      width,
      fontSize: 27,
      lineHeight: 1.5,
    }}
  >
    {children}
  </div>
);

const Scene: React.FC<{ part: number; chapter?: number }> = ({
  part,
  chapter = part,
}) => {
  const frame = useCurrentFrame();
  const wide = useVideoConfig().width > 1080;
  const dark = part === 0 || part === 5;
  const chapters = [
    "the problem",
    "a little spice",
    "real local previews",
    "preview before applying",
    "make it yours",
    "try the early build",
  ];
  const request =
    "Keep the logo crisp. Use a teal background, subtle gradients, and almost no glow.";
  const typed = request.slice(
    0,
    Math.floor(
      interpolate(frame, [15, 92], [0, request.length], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      }),
    ),
  );
  const rowSize = wide ? 130 : 125;
  return (
    <AbsoluteFill
      style={{
        background: dark ? "#171718" : paper,
        color: dark ? paper : ink,
        fontFamily: font,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 0.2,
          backgroundImage: `radial-gradient(${dark ? "#777" : "#aaa"} 1px, transparent 1px)`,
          backgroundSize: "32px 32px",
        }}
      />
      <div
        style={{
          position: "absolute",
          top: 48,
          left: 64,
          right: 64,
          display: "flex",
          alignItems: "center",
          gap: 12,
          fontSize: 21,
          fontWeight: 600,
        }}
      >
        <Img
          src={staticFile("app-icon.png")}
          style={{ width: 36, height: 36 }}
        />
        <span>Icon Spice</span>
        <span style={{ marginLeft: "auto", opacity: 0.5, fontSize: 17 }}>
          {String(chapter + 1).padStart(2, "0")} / {chapters[part]}
        </span>
      </div>
      <div
        style={{
          opacity: interpolate(frame, [0, 10], [0, 1], {
            extrapolateRight: "clamp",
          }),
        }}
      >
        {part === 0 && (
          <>
            <Head
              top={wide ? 250 : 155}
              width={wide ? 790 : 920}
              size={wide ? 96 : 79}
            >
              I called my Dock a<br />
              <span style={{ color: orange }}>grayscale graveyard.</span>
            </Head>
            <div
              style={{
                position: "absolute",
                left: wide ? 1040 : 80,
                top: wide ? 265 : 425,
                width: wide ? 760 : 920,
                height: wide ? 315 : 382,
                borderRadius: 24,
                overflow: "hidden",
                border: "1px solid #454545",
                transform: `translateY(${(1 - enter(frame, 10)) * 35}px)`,
                opacity: enter(frame, 10),
              }}
            >
              <Img
                src={staticFile("reference-tweet.png")}
                style={{
                  width: "100%",
                  position: "absolute",
                  top: wide ? -76 : -92,
                }}
              />
            </div>
            <Note top={wide ? 660 : 870}>
              So I decided to do something about it.
            </Note>
          </>
        )}
        {part === 1 && (
          <>
            <svg
              width="400"
              height="400"
              style={{
                position: "absolute",
                right: -100,
                top: 120,
                opacity: 0.5,
                transform: `rotate(${frame / 3}deg)`,
              }}
              viewBox="0 0 400 400"
            >
              <rect
                x="90"
                y="90"
                width="220"
                height="220"
                rx="40"
                fill="none"
                stroke={orange}
                strokeWidth="2"
              />
              <circle
                cx="200"
                cy="200"
                r="170"
                fill="none"
                stroke={purple}
                strokeWidth="2"
              />
            </svg>
            <div
              style={{
                position: "absolute",
                top: 190,
                left: 80,
                right: 80,
                textAlign: "center",
                fontSize: 29,
                color: purple,
                fontWeight: 600,
              }}
            >
              A native Mac app, born from that tweet.
            </div>
            <div
              style={{
                position: "absolute",
                top: 295,
                left: 65,
                right: 65,
                textAlign: "center",
                fontSize: wide ? 170 : 125,
                fontWeight: 780,
                letterSpacing: -7,
                transform: `translateY(${(1 - enter(frame, 8)) * 45}px)`,
              }}
            >
              Icon <span style={{ color: purple }}>Spice.</span>
            </div>
            <div
              style={{
                position: "absolute",
                top: wide ? 650 : 590,
                left: 0,
                right: 0,
                display: "flex",
                gap: wide ? 45 : 15,
                justifyContent: "center",
              }}
            >
              {icons.map((slug, i) => (
                <div
                  key={slug}
                  style={{
                    transform: `translateY(${(1 - enter(frame, 15 + i * 5)) * 90}px) rotate(${(1 - enter(frame, 15 + i * 5)) * (i % 2 ? 7 : -7)}deg)`,
                    opacity: enter(frame, 15 + i * 5),
                  }}
                >
                  <Icon slug={slug} size={wide ? 155 : 138} />
                </div>
              ))}
            </div>
            <div
              style={{
                position: "absolute",
                top: wide ? 873 : 821,
                left: 0,
                right: 0,
                textAlign: "center",
                fontSize: 31,
              }}
            >
              Give your apps a little more personality.
            </div>
          </>
        )}
        {part === 2 && (
          <>
            <Head
              top={wide ? 270 : 145}
              width={wide ? 620 : 920}
              size={wide ? 86 : 71}
            >
              Same logos.
              <br />
              <span style={{ color: purple }}>More personality.</span>
            </Head>
            <Note top={wide ? 570 : 325} width={wide ? 560 : 910}>
              Generated from the app’s own artwork.
              <br />
              No API key needed for local previews.
            </Note>
            <div
              style={{
                position: "absolute",
                top: wide ? 235 : 465,
                left: wide ? 790 : 80,
                width: wide ? 1050 : 920,
              }}
            >
              <div
                style={{
                  fontSize: 19,
                  letterSpacing: 2,
                  color: "#76746e",
                  marginBottom: 17,
                }}
              >
                ORIGINAL ARTWORK
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                {icons.map((slug) => (
                  <Icon key={slug} slug={slug} original size={rowSize} />
                ))}
              </div>
              <div style={{ height: 52 }} />
              <div
                style={{
                  fontSize: 19,
                  letterSpacing: 2,
                  color: purple,
                  marginBottom: 17,
                }}
              >
                ICON SPICE · LOCAL PREVIEWS
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                {icons.map((slug, i) => (
                  <div
                    key={slug}
                    style={{
                      textAlign: "center",
                      opacity: enter(frame, 10 + i * 8),
                      transform: `translateY(${(1 - enter(frame, 10 + i * 8)) * 25}px)`,
                    }}
                  >
                    <Icon slug={slug} size={rowSize} />
                    <div
                      style={{ fontSize: 17, marginTop: 14, color: "#77746e" }}
                    >
                      {names[i]}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </>
        )}
        {part === 3 && (
          <>
            <Head
              top={wide ? 255 : 145}
              width={wide ? 550 : 920}
              size={wide ? 78 : 71}
            >
              Preview first.
              <br />
              <span style={{ color: purple }}>Apply when ready.</span>
            </Head>
            <Note top={wide ? 530 : 315} width={wide ? 500 : 910}>
              Pick the icons you like.
              <br />
              Restore your previous icons anytime.
            </Note>
            <div
              style={{
                position: "absolute",
                left: wide ? 730 : 135,
                top: wide ? 175 : 425,
                width: wide ? 1100 : 810,
                borderRadius: 15,
                overflow: "hidden",
                boxShadow: "0 24px 70px #26212c22",
                transform: `translateY(${(1 - enter(frame)) * 28}px)`,
              }}
            >
              <div
                style={{
                  background: "#e6e4df",
                  height: 30,
                  display: "flex",
                  alignItems: "center",
                  paddingLeft: 15,
                  gap: 7,
                }}
              >
                {["#e97970", "#e8c36a", "#91bb78"].map((c) => (
                  <div
                    key={c}
                    style={{
                      width: 11,
                      height: 11,
                      borderRadius: 20,
                      background: c,
                    }}
                  />
                ))}
                <span
                  style={{
                    position: "absolute",
                    left: "45%",
                    fontSize: 14,
                    color: "#666",
                  }}
                >
                  Icon Spice
                </span>
              </div>
              <Img
                src={staticFile("library.png")}
                style={{ width: "100%", display: "block" }}
              />
            </div>
          </>
        )}
        {part === 4 && (
          <>
            <Head
              top={wide ? 255 : 155}
              width={wide ? 670 : 920}
              size={wide ? 83 : 73}
            >
              Your taste.
              <br />
              <span style={{ color: purple }}>Your instructions.</span>
            </Head>
            <Note top={wide ? 550 : 335} width={wide ? 580 : 900}>
              Optional AI customization.
              <br />
              Bring your own OpenAI key.
            </Note>
            <div
              style={{
                position: "absolute",
                left: wide ? 870 : 80,
                top: wide ? 285 : 490,
                width: 920,
                padding: 42,
                boxSizing: "border-box",
                borderRadius: 24,
                background: "#fff",
                border: "1px solid #ddd9e4",
                transform: `translateY(${(1 - enter(frame)) * 25}px)`,
              }}
            >
              <div
                style={{
                  display: "flex",
                  justifyContent: "space-between",
                  fontSize: 22,
                  marginBottom: 24,
                }}
              >
                <strong>What would you like to change?</strong>
                <span style={{ color: purple }}>✦ AI</span>
              </div>
              <div style={{ fontSize: 33, lineHeight: 1.4, minHeight: 150 }}>
                {typed}
                <span
                  style={{
                    opacity: Math.floor(frame / 15) % 2 ? 0 : 1,
                    color: purple,
                  }}
                >
                  |
                </span>
              </div>
              <div
                style={{ height: 1, background: "#edeaf1", margin: "25px 0" }}
              />
              <div style={{ fontSize: 20, color: "#757079" }}>
                Refine a preview or start from the original.
              </div>
            </div>
          </>
        )}
        {part === 5 && (
          <>
            <div
              style={{
                position: "absolute",
                top: 180,
                left: 0,
                right: 0,
                textAlign: "center",
              }}
            >
              <Img
                src={staticFile("app-icon.png")}
                style={{
                  width: 140,
                  height: 140,
                  transform: `scale(${0.92 + 0.08 * enter(frame)})`,
                }}
              />
            </div>
            <div
              style={{
                position: "absolute",
                top: 370,
                left: 60,
                right: 60,
                textAlign: "center",
                fontSize: wide ? 112 : 88,
                fontWeight: 750,
                lineHeight: 1.1,
                letterSpacing: -4,
              }}
            >
              A little spice.
              <br />
              <span style={{ color: orange }}>A more colorful Mac.</span>
            </div>
            <div
              style={{
                position: "absolute",
                top: 670,
                left: 60,
                right: 60,
                textAlign: "center",
                fontSize: 29,
              }}
            >
              Native macOS. Open source. Early build.
            </div>
            <div
              style={{
                position: "absolute",
                top: 760,
                left: 60,
                right: 60,
                textAlign: "center",
                fontSize: wide ? 39 : 31,
                color: "#c7bbff",
                fontWeight: 600,
              }}
            >
              github.com/dev-corolla/mac-icon-spice
            </div>
          </>
        )}
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 37,
          left: 64,
          right: 64,
          display: "flex",
          justifyContent: "space-between",
          fontSize: 17,
          opacity: 0.56,
        }}
      >
        <span>@corolladev</span>
        <span>macOS · open source · early build</span>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          height: 5,
          width: `${interpolate(frame, [0, part === 1 ? 120 : 180], [0, 100], { extrapolateRight: "clamp" })}%`,
          background: dark ? orange : purple,
        }}
      />
    </AbsoluteFill>
  );
};

export const LaunchVideo = () => (
  <AbsoluteFill>
    <Sequence durationInFrames={150}>
      <Scene part={0} />
    </Sequence>
    <Sequence from={150} durationInFrames={120}>
      <Scene part={1} />
    </Sequence>
    <Sequence from={270} durationInFrames={180}>
      <Scene part={2} />
    </Sequence>
    <Sequence from={450} durationInFrames={180}>
      <Scene part={3} />
    </Sequence>
    <Sequence from={630} durationInFrames={180}>
      <Scene part={4} />
    </Sequence>
    <Sequence from={810} durationInFrames={150}>
      <Scene part={5} />
    </Sequence>
  </AbsoluteFill>
);

export const ShortLaunchVideo = () => (
  <AbsoluteFill>
    <Sequence durationInFrames={90}>
      <Scene part={0} chapter={0} />
    </Sequence>
    <Sequence from={90} durationInFrames={150}>
      <Scene part={2} chapter={1} />
    </Sequence>
    <Sequence from={240} durationInFrames={120}>
      <Scene part={3} chapter={2} />
    </Sequence>
    <Sequence from={360} durationInFrames={90}>
      <Scene part={5} chapter={3} />
    </Sequence>
  </AbsoluteFill>
);
