//
//  SettingsManager.h
//  YouTubiliDanmaku
//
//  设置管理器
//

#import <Foundation/Foundation.h>

@interface SettingsManager : NSObject

+ (instancetype)shared;

// 弹幕开关
@property (nonatomic, assign) BOOL danmakuEnabled;

// 弹幕不透明度 (0.0 - 1.0)
@property (nonatomic, assign) float opacity;

// 弹幕字体大小倍率 (0.5 - 2.0)
@property (nonatomic, assign) float fontScale;

// 弹幕滚动速度倍率 (0.5 - 3.0)
@property (nonatomic, assign) float speedScale;

// 弹幕显示区域高度比例 (0.3 - 1.0)
@property (nonatomic, assign) float displayAreaRatio;

// 是否显示顶部弹幕
@property (nonatomic, assign) BOOL showTopDanmaku;

// 是否显示底部弹幕
@property (nonatomic, assign) BOOL showBottomDanmaku;

// 是否显示滚动弹幕
@property (nonatomic, assign) BOOL showScrollDanmaku;

// 弹幕密度上限（每屏最多同时显示的弹幕数）
@property (nonatomic, assign) int maxDensity;

// Bilibili Cookie（可选，用于绕过风控）
@property (nonatomic, copy) NSString *biliCookie;

// 自动匹配 Bilibili 视频
@property (nonatomic, assign) BOOL autoMatch;

// 保存设置
- (void)save;

@end
