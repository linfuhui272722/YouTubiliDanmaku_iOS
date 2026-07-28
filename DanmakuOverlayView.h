//
//  DanmakuOverlayView.h
//  YouTubiliDanmaku
//
//  弹幕渲染视图
//  覆盖在 YouTube 播放器之上，渲染滚动/顶部/底部弹幕
//

#import <UIKit/UIKit.h>
#import "DanmakuModel.h"

@interface DanmakuOverlayView : UIView

// 加载弹幕列表
- (void)loadDanmakus:(NSArray<Danmaku *> *)danmakus;

// 更新当前播放时间（秒）
- (void)updateCurrentTime:(NSTimeInterval)time;

// 暂停/恢复弹幕
- (void)pause;
- (void)resume;

// 清空弹幕
- (void)clear;

// 弹幕加载状态
@property (nonatomic, readonly) BOOL isLoading;

// 当前匹配的 Bilibili 视频信息
@property (nonatomic, copy) NSString *matchedBVID;
@property (nonatomic, copy) NSString *matchedTitle;

@end
