YouTubiliDanmaku (iOS)

⚠️ 当前状态：无法正常运行
此项目为个人实验性移植，因 Bilibili API 频繁变动（WBI 签名、token 校验等）以及 YouTube 版本差异，目前无法稳定获取弹幕。请勿安装，仅供代码参考。

本项目是 Chrome 扩展 you-tubili-danmaku 的 iOS 越狱移植版，尝试在 YouTube iOS 应用 播放视频时，自动根据视频标题搜索 Bilibili 匹配视频并拉取弹幕，以原生视图叠加渲染。

---

功能特性（理论支持，实际可能失效）

· 🔍 根据 YouTube 视频标题 + 频道名搜索 Bilibili 同名视频（依赖标题清洗算法）
· 📦 支持 Bilibili 新版 protobuf 弹幕接口（需 WBI 签名 + token）和旧版 XML 接口
· 🗜️ 支持 gzip / raw deflate 解压缩（弹幕接口返回压缩数据）
· 🎞️ 滚动 / 顶部 / 底部 / 逆向弹幕全模式（轨道分配算法）
· ⏱️ 时间同步：跟随 YouTube 播放进度，支持拖动重定位
· ⚙️ 设置面板：不透明度、字体大小、滚动速度、显示区域、弹幕类型开关
· 🍪 可选 Bilibili Cookie 配置（需包含 DedeUserID 和 bili_jct 才可能绕过部分风控）

---

已知问题 / 限制（核心障碍）

1. Bilibili API 强制 WBI 签名
   搜索、视频信息、弹幕接口均需计算 w_rid 和 wts 参数，代码中虽实现了签名逻辑，但密钥（imgKey/subKey）需从 /x/web-interface/nav 获取，且该接口需要 有效登录态 Cookie，否则无法得到密钥。
2. 弹幕接口需要 token
   /x/v2/dm/wbi/web/seg.so 要求携带从 /x/web-interface/view 返回的 token 字段，代码已做传递，但若 view 接口失败则弹幕无法获取。
3. Cookie 依赖严重
   即便实现签名，Bilibili 对未登录或风控 IP 仍可能返回 412/403 错误，需在设置面板手动输入完整 Cookie（包含 buvid3, buvid4, DedeUserID, bili_jct, SESSDATA 等）。
4. YouTube 版本兼容性
   内部播放器类名（如 YTPlayerViewController）在不同版本中可能变更，本项目 Hook 了多个常见类名，但无法保证覆盖所有版本。
5. 弹幕分段加载不全
   仅加载第一段弹幕（segment_index=1），长视频（>6分钟）后续分段未实现。

---

技术实现摘要

1. Bilibili API 客户端（BiliAPI.m）

基于 bilibili-API-collect 更新接口地址和签名逻辑：

接口 用途 当前实现
/x/web-interface/nav 获取 WBI 密钥（imgKey/subKey） ✅ 已实现，但需登录 Cookie
/x/web-interface/search/type 搜索视频 ✅ 已实现，需 WBI 签名
/x/web-interface/view 获取 CID 和 token ✅ 已实现，需 WBI 签名
/x/v2/dm/wbi/web/seg.so 获取弹幕（protobuf） ✅ 已实现，需 WBI 签名 + token

签名流程：

· 从 nav 接口获取 imgKey 和 subKey，拼接成 mixKey
· 对参数按 key 排序拼接，再拼接 mixKey 计算 MD5 得到 w_rid
· 将 w_rid 和 wts（当前时间戳）加入请求参数

解压处理：

· 自动检测 gzip 头部（0x1F 0x8B），使用 inflateInit2 解压，否则尝试 raw deflate

2. 视图注入与弹幕渲染（Tweak.x / DanmakuOverlayView.m）

· 使用 Logos Hook 播放器控制器，在视频切换时触发搜索
· 通过 CADisplayLink 驱动弹幕滚动，轨道分配基于屏幕高度和字体大小
· 固定弹幕（顶部/底部）定时自动移除

3. 设置面板（DanmakuControlView.m）

· 以 UITableView 底部弹出，使用 NSUserDefaults 持久化
· 修改实时生效（通过 NSNotification）

---

编译与安装（仅供开发者调试）

环境要求

· iOS 越狱设备（或 TrollStore + 注入工具）
· Theos 构建环境
· iPhone SDK（置于 $THEOS/sdks/）

编译步骤

```bash
export THEOS=/opt/theos
export PATH=$THEOS/bin:$PATH
cd YouTubiliDanmaku
make package FINALPACKAGE=1
```

生成的 .deb 位于 packages/ 目录。

注入方式

· 越狱：dpkg -i 安装，重启 SpringBoard
· 非越狱：使用 TrollFools 注入 YouTubiliDanmaku.dylib 到 YouTube 应用

---

目录结构

```
YouTubiliDanmaku/
├── Makefile
├── control
├── YouTubiliDanmaku.plist
├── Tweak.x                     # 主 Hook 入口
├── BiliAPI.h / .m              # Bilibili API（含 WBI 签名）
├── DanmakuModel.h / .m         # 数据模型
├── DanmakuOverlayView.h / .m   # 渲染视图
├── DanmakuControlView.h / .m   # 设置面板
├── SettingsManager.h / .m      # 持久化
├── LICENSE
└── README.md
```

---

未来改进方向（如果想让它跑起来）

1. 降低 Cookie 依赖：尝试使用公共代理或镜像接口，避免直接调用官方 API。
2. 完善错误回退：当 WBI 签名失败时，尝试使用旧版 seg.so 接口（无需签名但可能返回 XML）。
3. 增加自动重试机制：遇到 412/403 时等待后重试或提示用户更新 Cookie。
4. 支持更多 YouTube 版本：动态查找播放器视图，减少硬编码类名。

---

致谢

· you-tubili-danmaku（Chrome 扩展原型）
· bilibili-API-collect（API 文档参考）

License

MIT License – 详见 LICENSE
