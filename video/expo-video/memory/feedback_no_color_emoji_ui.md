---
name: feedback-no-color-emoji-ui
description: Uban App 畫面上不要彩色 emoji（按鈕、標題、提醒標題、開關圖示都改用圖示或純文字）
metadata:
  type: feedback
---

App 介面上的彩色 emoji 一律拿掉：已有 Material 圖示的按鈕／標題不要再加 emoji，提醒標題尾端的 emoji 顯示時用 `stripEmoji` 去掉，新加的開關或列也不要用 emoji 當圖示（例：「放上我的小豬」改用 `Icons.pets_rounded`）。

**Why:** 10-06 使用者多次指出「後面的彩色小圖示就不要了」，救生圈視窗、提醒標題、通話膠囊都因此改過。
**How to apply:** 新增或改版 UI 時預設不放 emoji；子代理產出的 UI 要檢查有沒有偷用 emoji。相關：[[project-elder-home-redesign]]
