//
//  Tweak.x
//  YouTubiliDanmaku
//
//  YouTube iOS 弹幕注入主逻辑
//
//  Hook 策略：
//  1. Hook YTPlayerViewController / MLVideoPlayer 等播放器控制器，获取当前视频标题和播放时间
//  2. 在播放器视图上添加 DanmakuOverlayView
//  3. 调用 BiliAPI 搜索并加载弹幕
//  4. 同步播放时间到弹幕视图
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

#import "DanmakuModel.h"
#import "BiliAPI.h"
#import "DanmakuOverlayView.h"
#import "SettingsManager.h"
#import "DanmakuControlView.h"

// ============================================================
// YouTube 类前向声明（运行时动态获取，避免硬编码头文件）
// ============================================================
@interface YTPlayerViewController : UIViewController
@end

// ============================================================
// 函数前向声明
// ============================================================
static BiliSearchResult *SelectBestMatch(NSArray<BiliSearchResult *> *results, NSString *title, NSString *channel);

// ============================================================
// 全局状态
// ============================================================
static DanmakuOverlayView *g_danmakuOverlay = nil;
static NSString *g_currentVideoID = nil;
static NSString *g_currentVideoTitle = nil;
static NSString *g_currentVideoChannel = nil;
static UIButton *g_danmakuButton = nil;
static UIView *g_playerContainerView = nil;
static NSTimer *g_timeUpdateTimer = nil;
static NSString *g_matchedBVID = nil;
static BOOL g_isLoadingDanmaku = NO;

// ============================================================
// 工具函数
// ============================================================

// 获取当前播放时间（秒）
static NSTimeInterval GetCurrentPlaybackTime() {
    if (!g_playerContainerView) return 0;

    // 尝试通过 responder chain 找到播放器控制器
    UIResponder *responder = g_playerContainerView.nextResponder;
    while (responder) {
        // 尝试通过 KVC 获取 currentPlayerTime / currentMediaTime / playbackTime
        id time = nil;
        @try { time = [responder valueForKey:@"currentPlayerTime"]; } @catch(NSException *e) {}
        if (!time) @try { time = [responder valueForKey:@"currentMediaTime"]; } @catch(NSException *e) {}
        if (!time) @try { time = [responder valueForKey:@"playbackTime"]; } @catch(NSException *e) {}
        if (!time) @try { time = [responder valueForKey:@"streamingTime"]; } @catch(NSException *e) {}

        if (time) {
            if ([time isKindOfClass:[NSNumber class]]) {
                return [(NSNumber *)time doubleValue];
            }
            if ([time isKindOfClass:[NSValue class]]) {
                // CMTime
                CMTime cmTime;
                @try {
                    [time getValue:&cmTime];
                    return CMTimeGetSeconds(cmTime);
                } @catch(NSException *e) {}
            }
        }

        responder = responder.nextResponder;
    }
    return 0;
}

// 获取最顶层的 window
static UIWindow *GetTopWindow() {
    for (UIWindow *window in [UIApplication sharedApplication].windows.reverseObjectEnumerator) {
        if (window.windowLevel == UIWindowLevelNormal && !window.hidden) {
            return window;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

// 按钮目标对象（前向声明）
@interface YouTubiliButtonTarget : NSObject
+ (instancetype)shared;
- (void)onTap;
@end

// 创建弹幕按钮
static void CreateDanmakuButton() {
    if (g_danmakuButton) return;

    UIWindow *window = GetTopWindow();
    if (!window) return;

    CGFloat buttonSize = 44;

    g_danmakuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    g_danmakuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    g_danmakuButton.layer.cornerRadius = buttonSize / 2;
    g_danmakuButton.layer.masksToBounds = YES;

    // 使用 SF Symbol
    UIImage *icon = [UIImage systemImageNamed:@"captions.bubble"];
    if (icon) {
        [g_danmakuButton setImage:icon forState:UIControlStateNormal];
        g_danmakuButton.tintColor = [UIColor whiteColor];
    } else {
        [g_danmakuButton setTitle:@"弹" forState:UIControlStateNormal];
        [g_danmakuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        g_danmakuButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    }

    [g_danmakuButton addTarget:[YouTubiliButtonTarget shared] action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

    [window addSubview:g_danmakuButton];

    // 自动布局
    g_danmakuButton.translatesAutoresizingMaskIntoConstraints = NO;
    [window addConstraints:@[
        // 修改：NSLayoutAttributeEqual -> NSLayoutRelationEqual
        [NSLayoutConstraint constraintWithItem:g_danmakuButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:window.safeAreaLayoutGuide attribute:NSLayoutAttributeTop multiplier:1 constant:16],
        [NSLayoutConstraint constraintWithItem:g_danmakuButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:window attribute:NSLayoutAttributeTrailing multiplier:1 constant:-16],
        [NSLayoutConstraint constraintWithItem:g_danmakuButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize],
        [NSLayoutConstraint constraintWithItem:g_danmakuButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:buttonSize],
    ]];
}

@implementation YouTubiliButtonTarget
+ (instancetype)shared {
    static YouTubiliButtonTarget *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YouTubiliButtonTarget alloc] init];
    });
    return instance;
}
- (void)onTap {
    [DanmakuControlView showInWindow:GetTopWindow()];
}
@end

// 创建/获取弹幕覆盖视图
static DanmakuOverlayView *EnsureDanmakuOverlay() {
    if (g_danmakuOverlay) return g_danmakuOverlay;
    if (!g_playerContainerView) return nil;

    g_danmakuOverlay = [[DanmakuOverlayView alloc] initWithFrame:g_playerContainerView.bounds];
    g_danmakuOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [g_playerContainerView addSubview:g_danmakuOverlay];

    return g_danmakuOverlay;
}

// 定时器目标
@interface YouTubiliTimerTarget : NSObject
+ (instancetype)shared;
- (void)tick;
@end

@implementation YouTubiliTimerTarget
+ (instancetype)shared {
    static YouTubiliTimerTarget *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YouTubiliTimerTarget alloc] init];
    });
    return instance;
}
- (void)tick {
    if (!g_danmakuOverlay) return;
    NSTimeInterval t = GetCurrentPlaybackTime();
    [g_danmakuOverlay updateCurrentTime:t];
}
@end

// 启动时间更新定时器
static void StartTimeUpdateTimer() {
    if (g_timeUpdateTimer) return;
    g_timeUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                         target:[YouTubiliTimerTarget shared]
                                                       selector:@selector(tick)
                                                       userInfo:nil
                                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:g_timeUpdateTimer forMode:NSRunLoopCommonModes];
}

static void StopTimeUpdateTimer() {
    [g_timeUpdateTimer invalidate];
    g_timeUpdateTimer = nil;
}

// ============================================================
// 加载弹幕
// ============================================================

static void LoadDanmakuForCurrentVideo() {
    if (g_isLoadingDanmaku) return;
    if (!g_currentVideoTitle || g_currentVideoTitle.length == 0) return;

    SettingsManager *s = [SettingsManager shared];
    if (!s.danmakuEnabled) return;

    g_isLoadingDanmaku = YES;
    g_matchedBVID = nil;

    // 清空旧弹幕
    if (g_danmakuOverlay) {
        [g_danmakuOverlay clear];
        g_danmakuOverlay.matchedBVID = nil;
        g_danmakuOverlay.matchedTitle = nil;
    }

    NSString *title = [g_currentVideoTitle copy];
    NSString *channel = [g_currentVideoChannel copy];

    NSLog(@"[YouTubili] Loading danmaku for: %@ (channel: %@)", title, channel);

    [[BiliAPI shared] searchVideoWithTitle:title channel:channel completion:^(NSArray<BiliSearchResult *> *results, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_isLoadingDanmaku = NO;

            if (error || results.count == 0) {
                NSLog(@"[YouTubili] No matching video found: %@", error ? error.localizedDescription : @"no results");
                return;
            }

            // 选择最佳匹配
            BiliSearchResult *best = SelectBestMatch(results, title, channel);
            if (!best) {
                NSLog(@"[YouTubili] No suitable match found");
                return;
            }

            NSLog(@"[YouTubili] Best match: %@ (%@)", best.title, best.bvid);
            g_matchedBVID = best.bvid;

            if (g_danmakuOverlay) {
                g_danmakuOverlay.matchedBVID = best.bvid;
                g_danmakuOverlay.matchedTitle = best.title;
            }

            // 获取弹幕
            [[BiliAPI shared] fetchDanmakuForBVID:best.bvid completion:^(NSArray<Danmaku *> *danmakus, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error || danmakus.count == 0) {
                        NSLog(@"[YouTubili] No danmaku found: %@", error ? error.localizedDescription : @"empty");
                        return;
                    }

                    NSLog(@"[YouTubili] Loaded %lu danmakus", (unsigned long)danmakus.count);

                    DanmakuOverlayView *overlay = EnsureDanmakuOverlay();
                    if (overlay) {
                        [overlay loadDanmakus:danmakus];
                        StartTimeUpdateTimer();
                    }
                });
            }];
        });
    }];
}

// 选择最佳匹配
// 注意：此处去掉了 static 修饰符以匹配前向声明，或者保持 static 并确保前向声明也带有 static (推荐做法)
// 但在 C 语言中，前向声明必须与定义完全匹配。这里保持 static 定义，前向声明也要加 static。
// 修正：最上方的前向声明已添加 static。
static BiliSearchResult *SelectBestMatch(NSArray<BiliSearchResult *> *results, NSString *title, NSString *channel) {
    if (results.count == 0) return nil;
    if (results.count == 1) return results[0];

    // 简单的相似度匹配
    BiliSearchResult *best = nil;
    CGFloat bestScore = 0;

    for (BiliSearchResult *r in results) {
        CGFloat score = 0;

        // 标题相似度
        NSString *rTitle = [r.title lowercaseString];
        NSString *qTitle = [title lowercaseString];
        if ([rTitle containsString:qTitle] || [qTitle containsString:rTitle]) {
            score += 1.0;
        }

        // 频道匹配
        if (channel.length > 0 && r.author.length > 0) {
            NSString *rAuthor = [r.author lowercaseString];
            NSString *qChannel = [channel lowercaseString];
            if ([rAuthor containsString:qChannel] || [qChannel containsString:rAuthor]) {
                score += 0.5;
            }
        }

        if (score > bestScore) {
            bestScore = score;
            best = r;
        }
    }

    return best ?: results[0];
}

// ============================================================
// Hook YouTube 播放器
// ============================================================

// Hook YTPlayerViewController 的 viewDidAppear
%hook YTPlayerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    NSLog(@"[YouTubili] YTPlayerViewController viewDidAppear");

    // 获取播放器视图
    UIView *playerView = nil;
    @try { playerView = [self valueForKey:@"playerView"]; } @catch(NSException *e) {}
    if (!playerView) {
        // 尝试从子视图找
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UIView class]] && v.bounds.size.width > 100 && v.bounds.size.height > 100) {
                playerView = v;
                break;
            }
        }
    }

    if (playerView) {
        g_playerContainerView = playerView;

        // 创建弹幕按钮
        CreateDanmakuButton();

        SettingsManager *s = [SettingsManager shared];
        if (s.danmakuEnabled) {
            EnsureDanmakuOverlay();
            StartTimeUpdateTimer();
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;

    // 清理
    if (g_danmakuOverlay) {
        [g_danmakuOverlay clear];
        [g_danmakuOverlay removeFromSuperview];
        g_danmakuOverlay = nil;
    }
    StopTimeUpdateTimer();
}

%end

// Hook 视频信息更新
// YouTube iOS 使用 YTPlayerViewController 的 setSingleVideo: 方法设置当前视频
%hook YTPlayerViewController

- (void)setSingleVideo:(id)video {
    %orig;

    NSLog(@"[YouTubili] setSingleVideo called");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *title = nil;
        NSString *channel = nil;
        NSString *videoID = nil;

        @try { title = [video valueForKey:@"title"]; } @catch(NSException *e) {}
        @try { channel = [video valueForKey:@"author"]; } @catch(NSException *e) {}
        if (!channel) @try { channel = [video valueForKey:@"channelName"]; } @catch(NSException *e) {}
        @try { videoID = [video valueForKey:@"videoId"]; } @catch(NSException *e) {}
        if (!videoID) @try { videoID = [video valueForKey:@"videoID"]; } @catch(NSException *e) {}

        if (title && ![title isEqualToString:g_currentVideoTitle ?: @""]) {
            g_currentVideoTitle = [title copy];
            g_currentVideoChannel = [channel copy];
            g_currentVideoID = [videoID copy];

            NSLog(@"[YouTubili] Video changed: %@ (channel: %@, id: %@)", title, channel, videoID);

            LoadDanmakuForCurrentVideo();
        }
    });
}

%end

// Hook ELPIVideoPlayer (新版 YouTube 使用的播放器)
%hook ELPIVideoPlayer

- (id)init {
    id ret = %orig;
    NSLog(@"[YouTubili] ELPIVideoPlayer init");
    return ret;
}

- (void)setCurrentVideo:(id)video {
    %orig;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString *title = nil;
        @try { title = [video valueForKey:@"title"]; } @catch(NSException *e) {}

        if (title && ![title isEqualToString:g_currentVideoTitle ?: @""]) {
            g_currentVideoTitle = [title copy];
            NSLog(@"[YouTubili] Video changed (ELPI): %@", title);
            LoadDanmakuForCurrentVideo();
        }
    });
}

%end

// ============================================================
// 构造函数：初始化
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"[YouTubili] Tweak loaded into YouTube");

        // 初始化设置
        [SettingsManager shared];

        // 监听设置变化
        [[NSNotificationCenter defaultCenter] addObserverForName:@"YouTubiliSettingsChanged"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            SettingsManager *s = [SettingsManager shared];
            if (!s.danmakuEnabled) {
                if (g_danmakuOverlay) {
                    [g_danmakuOverlay clear];
                    [g_danmakuOverlay removeFromSuperview];
                    g_danmakuOverlay = nil;
                }
                if (g_danmakuButton) {
                    [g_danmakuButton removeFromSuperview];
                    g_danmakuButton = nil;
                }
                StopTimeUpdateTimer();
            } else {
                // 重新加载弹幕
                if (g_currentVideoTitle) {
                    LoadDanmakuForCurrentVideo();
                }
            }
        }];
    }
}
