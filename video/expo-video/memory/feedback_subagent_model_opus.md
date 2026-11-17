---
name: feedback-subagent-model-opus
description: 主對話用 Fable 時，子代理一律用 Opus，不要用 Fable 平行跑
metadata:
  type: feedback
---

主對話在 Fable 上時，派出去的子代理用 `model: opus`，不要用 `fable`。

**Why:** 2026-11-16 使用者先說「用 fable 去跑」，4 個 Fable 子代理平行跑分鏡後連續兩次撞到 5 小時用量上限（工作中斷到重置才能接），使用者改口：「只有主要的才跑 fable 好了，其他子代理用 opus」。

**How to apply:** 規劃、審查、和使用者對話留在主對話；起草、換皮、渲染等派工用 Opus 子代理。這取代 [[project-expo-video]] 與 Uban/CLAUDE.md 裡「Sonnet 子代理執行」的舊分工，除非使用者另外指定。
