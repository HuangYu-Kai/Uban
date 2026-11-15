import React from "react";
import { Composition } from "remotion";
import { UbanPromo, FPS, TOTAL_FRAMES } from "./UbanPromo";
import { ChatFeature, CHAT_FPS, CHAT_FRAMES } from "./ChatFeature";
import { PainPoints, PAIN_FPS, PAIN_FRAMES } from "./PainPoints";
import { Ad, AD_FPS, AD60_FRAMES, AD15_FRAMES } from "./Ad";
import { Ch01, CH01_FRAMES } from "./demo/Ch01";
import { Ch02, CH02_FRAMES } from "./demo/Ch02";
import { Ch03, CH03_FRAMES } from "./demo/Ch03";
import { Ch04, CH04_FRAMES } from "./demo/Ch04";
import { Ch05, CH05_FRAMES } from "./demo/Ch05";
import { Ch07, CH07_FRAMES } from "./demo/Ch07";
import { Ch08, CH08_FRAMES } from "./demo/Ch08";
import { Ch10, CH10_FRAMES } from "./demo/Ch10";

export const Root: React.FC = () => (
  <>
    <Composition id="UbanPromo" component={UbanPromo} durationInFrames={TOTAL_FRAMES} fps={FPS} width={1920} height={1080} />
    <Composition id="PainPoints" component={PainPoints} durationInFrames={PAIN_FRAMES} fps={PAIN_FPS} width={1920} height={1080} />
    <Composition id="ChatFeature" component={ChatFeature} durationInFrames={CHAT_FRAMES} fps={CHAT_FPS} width={1920} height={1080} />
    {/* 展示影片（長版）：每章一個 composition */}
    <Composition id="Ch01" component={Ch01} durationInFrames={CH01_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch02" component={Ch02} durationInFrames={CH02_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch03" component={Ch03} durationInFrames={CH03_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch04" component={Ch04} durationInFrames={CH04_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch05" component={Ch05} durationInFrames={CH05_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch07" component={Ch07} durationInFrames={CH07_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch08" component={Ch08} durationInFrames={CH08_FRAMES} fps={30} width={1920} height={1080} />
    <Composition id="Ch10" component={Ch10} durationInFrames={CH10_FRAMES} fps={30} width={1920} height={1080} />
    {/* 廣告：同一套鏡頭，換時間軸（cut）與版面（layout） */}
    <Composition id="Ad60" component={Ad} durationInFrames={AD60_FRAMES} fps={AD_FPS} width={1920} height={1080} defaultProps={{ layout: "wide" as const, cut: "full" as const }} />
    <Composition id="Ad15" component={Ad} durationInFrames={AD15_FRAMES} fps={AD_FPS} width={1920} height={1080} defaultProps={{ layout: "wide" as const, cut: "short" as const }} />
    <Composition id="Ad60V" component={Ad} durationInFrames={AD60_FRAMES} fps={AD_FPS} width={1080} height={1920} defaultProps={{ layout: "tall" as const, cut: "full" as const }} />
  </>
);
