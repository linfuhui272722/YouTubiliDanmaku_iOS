//
//  DanmakuOverlayView.m
//  YouTubiliDanmaku
//
//  弹幕渲染视图实现
//  使用 CADisplayLink 驱动动画，模拟 Bilibili 弹幕效果
//

#import "DanmakuOverlayView.h"
#import "SettingsManager.h"

// 轨道高度
static const CGFloat kTrackHeight = 32;
// 滚动弹幕默认时长（秒）
static const NSTimeInterval kScrollDuration = 8.0;
// 固定弹幕显示时长（秒）
static const NSTimeInterval kFixedDuration = 4.0;

// 修复：使用 #define 宏定义数组大小，确保编译期常量
#define kScrollTrackCount 12
#define kFixedTrackCount 6

// 单条滚动弹幕的运行时数据
@interface ScrollDanmakuItem : NSObject
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) CGFloat startX;
@property (nonatomic, assign) CGFloat endX;
@property (nonatomic, assign) CGFloat currentX;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) int track;
@end

@implementation ScrollDanmakuItem
@end

// 固定弹幕（顶部/底部）
@interface FixedDanmakuItem : NSObject
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) BOOL isTop;
@property (nonatomic, assign) int track;
@end

@implementation FixedDanmakuItem
@end


@interface DanmakuOverlayView ()
{
    CADisplayLink *_displayLink;
    CFTimeInterval _lastTimestamp;

    // 所有弹幕（按时间排序）
    NSArray<Danmaku *> *_allDanmakus;
    NSInteger _nextDanmakuIndex;

    // 当前正在显示的滚动弹幕
    NSMutableArray<ScrollDanmakuItem *> *_activeScrollItems;
    // 当前正在显示的固定弹幕
    NSMutableArray<FixedDanmakuItem *> *_activeFixedItems;

    // 轨道占用时间（用于分配轨道）
    // 使用宏定义确保数组大小是编译期常量
    NSTimeInterval _scrollTrackAvailable[kScrollTrackCount];
    NSTimeInterval _topTrackAvailable[kFixedTrackCount];
    NSTimeInterval _bottomTrackAvailable[kFixedTrackCount];

    // 当前播放时间
    NSTimeInterval _currentTime;
    BOOL _paused;

    // 容器视图（用于添加弹幕 label）
    UIView *_containerView;

    // 基础字体
    UIFont *_baseFont;
}

@property (nonatomic, assign) BOOL isLoading;

@end

@implementation DanmakuOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;

        _containerView = [[UIView alloc] initWithFrame:self.bounds];
        _containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _containerView.userInteractionEnabled = NO;
        [self addSubview:_containerView];

        _activeScrollItems = [NSMutableArray array];
        _activeFixedItems = [NSMutableArray array];

        _baseFont = [UIFont boldSystemFontOfSize:18];

        [self resetTracks];
        [self startDisplayLink];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(settingsChanged)
                                                     name:@"YouTubiliSettingsChanged"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self stopDisplayLink];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)resetTracks {
    for (int i = 0; i < kScrollTrackCount; i++) _scrollTrackAvailable[i] = 0;
    for (int i = 0; i < kFixedTrackCount; i++) _topTrackAvailable[i] = 0;
    for (int i = 0; i < kFixedTrackCount; i++) _bottomTrackAvailable[i] = 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _containerView.frame = self.bounds;
}

#pragma mark - 加载弹幕

- (void)loadDanmakus:(NSArray<Danmaku *> *)danmakus {
    [self clear];

    // 按时间排序
    _allDanmakus = [danmakus sortedArrayUsingComparator:^NSComparisonResult(Danmaku *a, Danmaku *b) {
        if (a.time < b.time) return NSOrderedAscending;
        if (a.time > b.time) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    _nextDanmakuIndex = 0;
    _isLoading = NO;

    NSLog(@"[YouTubili] Loaded %lu danmakus for display", (unsigned long)_allDanmakus.count);
}

- (void)updateCurrentTime:(NSTimeInterval)time {
    if (_paused) return;

    // 处理时间跳变（如拖动进度条）
    if (time < _currentTime - 1.0 || time > _currentTime + 5.0) {
        // 时间跳变，清空当前弹幕
        [self clearActiveItems];
        _nextDanmakuIndex = 0;
        // 找到当前时间附近的弹幕
        for (NSInteger i = 0; i < _allDanmakus.count; i++) {
            if (_allDanmakus[i].time >= time) {
                _nextDanmakuIndex = i;
                break;
            }
        }
    }

    _currentTime = time;

    // 检查是否有新弹幕需要显示
    while (_nextDanmakuIndex < _allDanmakus.count) {
        Danmaku *d = _allDanmakus[_nextDanmakuIndex];
        if (d.time > _currentTime + 0.1) break;

        [self spawnDanmaku:d];
        _nextDanmakuIndex++;
    }
}

- (void)clearActiveItems {
    for (ScrollDanmakuItem *item in _activeScrollItems) {
        [item.label removeFromSuperview];
    }
    for (FixedDanmakuItem *item in _activeFixedItems) {
        [item.label removeFromSuperview];
    }
    [_activeScrollItems removeAllObjects];
    [_activeFixedItems removeAllObjects];
    [self resetTracks];
}

- (void)clear {
    [self clearActiveItems];
    _allDanmakus = nil;
    _nextDanmakuIndex = 0;
    _currentTime = 0;
}

- (void)pause {
    _paused = YES;
    if (_displayLink) {
        _displayLink.paused = YES;
    }
}

- (void)resume {
    _paused = NO;
    if (_displayLink) {
        _displayLink.paused = NO;
        _lastTimestamp = 0;
    }
}

#pragma mark - DisplayLink

- (void)startDisplayLink {
    if (_displayLink) return;
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _displayLink.frameInterval = 1;
}

- (void)stopDisplayLink {
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)tick:(CADisplayLink *)link {
    if (_paused) return;

    CFTimeInterval now = CACurrentMediaTime();
    if (_lastTimestamp == 0) {
        _lastTimestamp = now;
        return;
    }
    CFTimeInterval delta = now - _lastTimestamp;
    _lastTimestamp = now;

    SettingsManager *s = [SettingsManager shared];

    // 更新滚动弹幕位置
    NSMutableArray *toRemove = [NSMutableArray array];
    for (ScrollDanmakuItem *item in _activeScrollItems) {
        NSTimeInterval elapsed = _currentTime - item.startTime;
        if (elapsed < 0) continue;

        CGFloat progress = elapsed / item.duration;
        if (progress >= 1.0) {
            [toRemove addObject:item];
            continue;
        }

        item.currentX = item.startX + (item.endX - item.startX) * progress;
        item.label.frame = CGRectMake(item.currentX, item.y, item.width, kTrackHeight);
    }
    for (ScrollDanmakuItem *item in toRemove) {
        [item.label removeFromSuperview];
        [_activeScrollItems removeObject:item];
    }

    // 更新固定弹幕
    NSMutableArray *fixedToRemove = [NSMutableArray array];
    for (FixedDanmakuItem *item in _activeFixedItems) {
        NSTimeInterval elapsed = _currentTime - item.startTime;
        if (elapsed >= item.duration) {
            [fixedToRemove addObject:item];
        }
    }
    for (FixedDanmakuItem *item in fixedToRemove) {
        [item.label removeFromSuperview];
        [_activeFixedItems removeObject:item];
    }
}

#pragma mark - 生成弹幕

- (void)spawnDanmaku:(Danmaku *)d {
    if (!d.text || d.text.length == 0) return;

    SettingsManager *s = [SettingsManager shared];

    // 密度限制
    if (_activeScrollItems.count + _activeFixedItems.count >= s.maxDensity) return;

    // 根据模式分发
    switch (d.mode) {
        case 1: case 2: case 3: // 滚动
            if (s.showScrollDanmaku) {
                [self spawnScrollDanmaku:d];
            }
            break;
        case 4: // 底部
            if (s.showBottomDanmaku) {
                [self spawnFixedDanmaku:d isTop:NO];
            }
            break;
        case 5: // 顶部
            if (s.showTopDanmaku) {
                [self spawnFixedDanmaku:d isTop:YES];
            }
            break;
        case 6: // 逆向
            if (s.showScrollDanmaku) {
                [self spawnScrollDanmaku:d reverse:YES];
            }
            break;
        default:
            if (s.showScrollDanmaku) {
                [self spawnScrollDanmaku:d];
            }
            break;
    }
}

- (void)spawnScrollDanmaku:(Danmaku *)d reverse:(BOOL)reverse {
    SettingsManager *s = [SettingsManager shared];

    // 计算字体
    CGFloat fontSize = 18 * s.fontScale;
    if (d.fontSize == 18) fontSize = 18 * s.fontScale;
    else if (d.fontSize == 25) fontSize = 25 * s.fontScale;
    else fontSize = d.fontSize * s.fontScale;

    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];

    // 计算文本宽度
    CGSize textSize = [d.text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, kTrackHeight)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: font}
                                            context:nil].size;
    CGFloat width = ceil(textSize.width) + 8;

    // 找一个可用轨道
    int track = -1;
    CGFloat viewWidth = self.bounds.size.width;
    if (viewWidth <= 0) viewWidth = [UIScreen mainScreen].bounds.size.width;

    // 显示区域高度
    CGFloat viewHeight = self.bounds.size.height;
    if (viewHeight <= 0) viewHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat displayHeight = viewHeight * s.displayAreaRatio;
    int maxTracks = (int)(displayHeight / kTrackHeight);
    if (maxTracks > kScrollTrackCount) maxTracks = kScrollTrackCount;
    if (maxTracks < 1) maxTracks = 1;

    for (int i = 0; i < maxTracks; i++) {
        if (_scrollTrackAvailable[i] <= _currentTime) {
            track = i;
            break;
        }
    }
    if (track < 0) return;

    // 创建 label
    UILabel *label = [[UILabel alloc] init];
    label.text = d.text;
    label.font = font;
    label.textColor = [self colorFromBiliColor:d.color];
    label.alpha = s.opacity;
    label.backgroundColor = [UIColor clearColor];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(0, 0);
    label.layer.shadowRadius = 2.0;
    label.layer.shadowOpacity = 0.8;

    // 计算位置
    CGFloat y = track * kTrackHeight + 2;
    CGFloat startX, endX;
    if (reverse) {
        startX = -width;
        endX = viewWidth;
    } else {
        startX = viewWidth;
        endX = -width;
    }

    label.frame = CGRectMake(startX, y, width, kTrackHeight);
    [_containerView addSubview:label];

    ScrollDanmakuItem *item = [ScrollDanmakuItem new];
    item.label = label;
    item.startX = startX;
    item.endX = endX;
    item.currentX = startX;
    item.y = y;
    item.width = width;
    item.duration = kScrollDuration / s.speedScale;
    item.startTime = _currentTime;
    item.track = track;
    [_activeScrollItems addObject:item];

    // 计算轨道占用时间
    // 当弹幕完全进入屏幕时，该轨道才能放下一条弹幕
    CGFloat travelDistance = viewWidth + width;
    CGFloat enterDistance = width;
    NSTimeInterval totalTime = item.duration;
    NSTimeInterval enterTime = totalTime * (enterDistance / travelDistance);
    _scrollTrackAvailable[track] = _currentTime + enterTime + 0.1;
}

- (void)spawnScrollDanmaku:(Danmaku *)d {
    [self spawnScrollDanmaku:d reverse:NO];
}

- (void)spawnFixedDanmaku:(Danmaku *)d isTop:(BOOL)isTop {
    SettingsManager *s = [SettingsManager shared];

    CGFloat fontSize = 18 * s.fontScale;
    if (d.fontSize == 18) fontSize = 18 * s.fontScale;
    else if (d.fontSize == 25) fontSize = 25 * s.fontScale;
    else fontSize = d.fontSize * s.fontScale;

    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];

    CGSize textSize = [d.text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, kTrackHeight)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: font}
                                            context:nil].size;
    CGFloat width = ceil(textSize.width) + 8;

    // 找轨道
    int track = -1;
    NSTimeInterval *tracks = isTop ? _topTrackAvailable : _bottomTrackAvailable;
    for (int i = 0; i < kFixedTrackCount; i++) {
        if (tracks[i] <= _currentTime) {
            track = i;
            break;
        }
    }
    if (track < 0) return;

    UILabel *label = [[UILabel alloc] init];
    label.text = d.text;
    label.font = font;
    label.textColor = [self colorFromBiliColor:d.color];
    label.alpha = s.opacity;
    label.backgroundColor = [UIColor clearColor];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(0, 0);
    label.layer.shadowRadius = 2.0;
    label.layer.shadowOpacity = 0.8;

    CGFloat x = (self.bounds.size.width - width) / 2;
    CGFloat y;
    if (isTop) {
        y = track * kTrackHeight + 4;
    } else {
        y = self.bounds.size.height - (track + 1) * kTrackHeight - 4;
    }
    label.frame = CGRectMake(x, y, width, kTrackHeight);
    [_containerView addSubview:label];

    FixedDanmakuItem *item = [FixedDanmakuItem new];
    item.label = label;
    item.startTime = _currentTime;
    item.duration = kFixedDuration;
    item.isTop = isTop;
    item.track = track;
    [_activeFixedItems addObject:item];

    tracks[track] = _currentTime + kFixedDuration + 0.1;
}

- (UIColor *)colorFromBiliColor:(uint32_t)color {
    CGFloat r = ((color >> 16) & 0xFF) / 255.0;
    CGFloat g = ((color >> 8) & 0xFF) / 255.0;
    CGFloat b = (color & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

- (void)settingsChanged {
    SettingsManager *s = [SettingsManager shared];
    // 不需要重新创建视图，下次生成弹幕时会使用新设置
}

@end
