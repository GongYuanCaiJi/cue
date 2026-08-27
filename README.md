# cue

半透明的「念稿浮窗」。把任何一個視窗（例如瀏覽器開的講稿）**半透明疊在螢幕最上層**，可自由移動、縮放、調透明度，讓你在視訊面試或錄影時，一邊看鏡頭一邊念稿。

選單列常駐一顆圖釘圖示，點它 → **Pin Window...** → 挑要念的視窗即可。

## 功能

- **鏡像任一視窗**：用 ScreenCaptureKit 即時鏡像你選的視窗內容
- **浮在最上層**：包含全螢幕 app 和其他 Space 之上
- **可移動 / 縮放**：中間拖曳移動、邊緣拖曳縮放
- **可調透明度**：選單裡的 opacity 滑桿
- **穩定的視窗清單**：跨 Space、含被遮住的視窗都列得出來，同一個 app 的多個視窗獨立列出

## 建置

不需要完整 Xcode（用 `swiftc` + 系統 framework）：

```sh
sh build.sh
```

會編譯 → 打包 → 簽章 → 安裝到 `/Applications/cue.app` 並啟動。簽章細節見 `build.sh` 註解。

## 出處與授權

Fork 自 [southflowpeak/Pin](https://github.com/southflowpeak/Pin)（MIT）。核心的視窗鏡像與 click-through 來自上游；本版新增可移動/縮放的浮窗、修好視窗清單列舉，並改用本機自簽憑證簽章。沿用 MIT 授權。
