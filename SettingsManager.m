//
//  SettingsManager.m
//  YouTubiliDanmaku
//

#import "SettingsManager.h"

static NSString *const kDefaultsKey = @"com.youtubili.danmaku.settings";

@implementation SettingsManager

+ (instancetype)shared {
    static SettingsManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SettingsManager alloc] init];
        [instance load];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 默认值
        _danmakuEnabled = YES;
        _opacity = 1.0;
        _fontScale = 1.0;
        _speedScale = 1.0;
        _displayAreaRatio = 0.85;
        _showTopDanmaku = YES;
        _showBottomDanmaku = YES;
        _showScrollDanmaku = YES;
        _maxDensity = 100;
        _biliCookie = @"";
        _autoMatch = YES;
    }
    return self;
}

- (void)load {
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsKey];
    if (!dict) return;

    if (dict[@"danmakuEnabled"])   _danmakuEnabled = [dict[@"danmakuEnabled"] boolValue];
    if (dict[@"opacity"])          _opacity = [dict[@"opacity"] floatValue];
    if (dict[@"fontScale"])        _fontScale = [dict[@"fontScale"] floatValue];
    if (dict[@"speedScale"])       _speedScale = [dict[@"speedScale"] floatValue];
    if (dict[@"displayAreaRatio"]) _displayAreaRatio = [dict[@"displayAreaRatio"] floatValue];
    if (dict[@"showTopDanmaku"])   _showTopDanmaku = [dict[@"showTopDanmaku"] boolValue];
    if (dict[@"showBottomDanmaku"]) _showBottomDanmaku = [dict[@"showBottomDanmaku"] boolValue];
    if (dict[@"showScrollDanmaku"]) _showScrollDanmaku = [dict[@"showScrollDanmaku"] boolValue];
    if (dict[@"maxDensity"])       _maxDensity = [dict[@"maxDensity"] intValue];
    if (dict[@"biliCookie"])       _biliCookie = dict[@"biliCookie"];
    if (dict[@"autoMatch"])        _autoMatch = [dict[@"autoMatch"] boolValue];
}

- (void)save {
    NSDictionary *dict = @{
        @"danmakuEnabled":   @(_danmakuEnabled),
        @"opacity":          @(_opacity),
        @"fontScale":        @(_fontScale),
        @"speedScale":       @(_speedScale),
        @"displayAreaRatio": @(_displayAreaRatio),
        @"showTopDanmaku":   @(_showTopDanmaku),
        @"showBottomDanmaku":@(_showBottomDanmaku),
        @"showScrollDanmaku":@(_showScrollDanmaku),
        @"maxDensity":       @(_maxDensity),
        @"biliCookie":       _biliCookie ?: @"",
        @"autoMatch":        @(_autoMatch),
    };
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 发送通知，让弹幕视图刷新
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YouTubiliSettingsChanged" object:nil];
}

@end
