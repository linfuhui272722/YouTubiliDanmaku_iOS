# YouTubiliDanmaku (iOS)

> 将 Bilibili 弹幕移植到 YouTube iOS 应用 — 越狱插件 (Theos / Logos)

本项目是 Chrome 扩展 [you-tubili-danmaku](https://gitee.com/Drom1145/you-tubili-danmaku) 的 iOS 越狱移植版。

在 **YouTube iOS 应用** 播放视频时，自动根据视频标题在 **Bilibili** 上搜索匹配的视频，拉取弹幕，并以原生 `UILabel` + `CADisplayLink` 的方式叠加在播放器上方渲染。

---

## 功能特性

- ✅ 自动根据 YouTube 视频标题 + 频道名搜索 Bilibili 同名视频
- ✅ 支持 Bilibili 新版 protobuf 弹幕接口 (`seg.so`) 和旧版 XML 弹幕接口
- ✅ 支持 raw deflate 解压缩（Bilibili 弹幕接口返回压缩数据）
- ✅ 滚动弹幕 / 顶部弹幕 / 底部弹幕 / 逆向弹幕 全模式支持
- ✅ 轨道分配算法，避免弹幕重叠
- ✅ 时间同步：跟随 YouTube 播放进度，支持拖动进度条后自动重定位
- ✅ 设置面板：不透明度、字体大小、滚动速度、显示区域、弹幕类型开关
- ✅ 可选 Bilibili Cookie 配置，绕过风控
- ✅ 弹幕密度限制，性能可控

## 截图

（播放 YouTube 视频，弹幕从右向左滚动，效果与 Bilibili 一致）

## 系统要求

| 项目 | 要求 |
|------|------|
| 设备 | iPhone / iPad（arm64 / arm64e） |
| 系统 | iOS 14.0+（有根越狱 rootful） |
| 越狱环境 | checkra1n / palera1n-rootful / Dopamine(rootful) 等 |
| YouTube 版本 | 任意（理论兼容，不同版本 Hook 点可能需微调） |
| 编译工具链 | Theos + iPhone SDK |

## 安装

### 方式一：直接安装 deb

1. 将 `YouTubiliDanmaku.deb` 通过 Filza / SSH 拷贝到设备
2. 执行 `dpkg -i YouTubiliDanmaku.deb`
3. 注销（respring）
4. 打开 YouTube 应用，播放任意视频

### 方式二：加入 Cydia/Sileo 源

将 deb 放入你的私有源，添加源地址后安装。

## 使用说明

1. 打开 YouTube 应用，播放任意视频
2. 屏幕右上角会出现一个弹幕图标按钮（半透明圆形）
3. 点击该按钮可打开设置面板：
   - 启用/禁用弹幕
   - 调整不透明度、字体大小、滚动速度、显示区域
   - 开关滚动/顶部/底部弹幕
   - 配置 Bilibili Cookie（可选，用于绕过风控）
   - 开关自动匹配
4. 弹幕会自动根据视频标题在 Bilibili 搜索匹配视频并加载

## 编译

### 环境准备

1. 安装 [Theos](https://theos.dev/docs/installation)
2. 配置 iPhone SDK（放置于 `$THEOS/sdks/`）
3. 设置环境变量：
   ```bash
   export THEOS=/opt/theos
   export PATH=$THEOS/bin:$PATH
   ```

### 编译

```bash
cd YouTubiliDanmaku
make package FINALPACKAGE=1
```

编译产物：`packages/com.youtubili.danmaku_1.0.0_iphoneos-arm.deb`

## 项目结构

```
YouTubiliDanmaku/
├── Makefile                  # Theos 编译配置
├── control                   # deb 包元信息
├── YouTubiliDanmaku.plist    # 注入目标（com.google.ios.youtube）
├── Tweak.x                   # Logos 主 Hook 文件
├── BiliAPI.h / .m            # Bilibili API 客户端（搜索/视频信息/弹幕）
├── DanmakuModel.h / .m       # 弹幕数据模型
├── DanmakuOverlayView.h / .m # 弹幕渲染视图（CADisplayLink 驱动）
├── DanmakuControlView.h / .m  # 设置面板 UI
├── SettingsManager.h / .m    # 设置持久化
├── LICENSE
└── README.md
```

## 技术实现

### 1. Bilibili 弹幕获取（`BiliAPI.m`）

移植自 Chrome 扩展的 `background.js`，包含三个核心 API：

| API | 用途 |
|-----|------|
| `searchVideoWithTitle:channel:` | 按标题搜索 Bilibili 视频 |
| `fetchVideoInfoWithBVID:` | 通过 BV 号获取视频 CID |
| `fetchDanmakuWithCID:` | 通过 CID 获取弹幕列表 |

**弹幕格式解析**：
- 新版接口 (`seg.so`)：返回 **raw deflate 压缩的 protobuf** 数据
  - 先用 `zlib` 的 `inflateInit2(windowBits=-15)` 解压
  - 再手写 protobuf varint 解析器提取 `DanmakuElem` 字段
- 旧版接口 (`cid.xml`)：返回 XML，用 `NSXMLParser` 解析

### 2. YouTube 应用 Hook（`Tweak.x`）

使用 Logos 语法 Hook YouTube 的播放器控制器：

```objc
%hook YTPlayerViewController
- (void)setSingleVideo:(id)video {
    %orig;
    // 从 video 对象 KVC 提取 title / author / videoId
    // 触发弹幕加载
}
%end
```

**播放时间获取**：通过 responder chain 遍历，KVC 尝试 `currentPlayerTime` / `currentMediaTime` / `playbackTime` / `streamingTime` 等属性，兼容不同 YouTube 版本。

**视图注入**：在 `YTPlayerViewController.viewDidAppear:` 中找到播放器视图，添加 `DanmakuOverlayView` 作为子视图。

### 3. 弹幕渲染（`DanmakuOverlayView.m`）

- 使用 `CADisplayLink` 驱动 60fps 动画
- 滚动弹幕：从右向左线性插值移动，`progress = elapsed / duration`
- 轨道分配：维护每条轨道的"可用时间"数组，弹幕完全进入屏幕后才释放轨道
- 固定弹幕（顶部/底部）：居中显示 4 秒后移除
- 时间跳变检测：拖动进度条时自动清空并重新定位弹幕索引

### 4. 设置面板（`DanmakuControlView.m`）

- 底部弹出的 `UITableView` 设置面板
- `UISwitch` 开关 + `UISlider` 滑块
- 设置通过 `NSUserDefaults` 持久化
- 修改后发送 `YouTubiliSettingsChanged` 通知，实时生效

## 已知限制

1. **视频匹配依赖标题相似度**：如果 YouTube 视频标题与 Bilibili 上的标题差异较大，可能匹配失败。可在设置面板手动配置。
2. **YouTube 版本兼容性**：不同版本的 YouTube iOS 应用内部类名可能变化（如 `YTPlayerViewController` → `ELPIVideoPlayer`），本项目已 Hook 多个常见类名，但未来版本可能需要补充。
3. **Bilibili 风控**：频繁请求可能触发风控，建议在设置面板配置 Cookie。
4. **弹幕分段**：当前只加载第一段弹幕（`segment_index=1`），超长视频（>6分钟）的后续弹幕段未加载。

## 致谢

- 原始 Chrome 扩展：[you-tubili-danmaku](https://gitee.com/Drom1145/you-tubili-danmaku)
- Bilibili API 文档参考：[SocialSisterYi/bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)

## License

MIT License - 详见 [LICENSE](LICENSE)
