//
//  DanmakuControlView.m
//  YouTubiliDanmaku
//

#import "DanmakuControlView.h"
#import "SettingsManager.h"

@interface DanmakuControlView () <UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *backgroundView;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation DanmakuControlView

+ (void)showInWindow:(UIWindow *)window {
    if (!window) return;
    // 避免重复显示
    for (UIView *v in window.subviews) {
        if ([v isKindOfClass:[DanmakuControlView class]]) return;
    }
    DanmakuControlView *view = [[DanmakuControlView alloc] initWithFrame:window.bounds];
    [window addSubview:view];

    // 入场动画
    view.panelView.transform = CGAffineTransformMakeTranslation(0, view.panelView.bounds.size.height);
    view.backgroundView.alpha = 0;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        view.panelView.transform = CGAffineTransformIdentity;
        view.backgroundView.alpha = 1;
    } completion:nil];
}

+ (void)dismiss {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        for (UIView *v in [window.subviews copy]) {
            if ([v isKindOfClass:[DanmakuControlView class]]) {
                DanmakuControlView *cv = (DanmakuControlView *)v;
                [UIView animateWithDuration:0.25 animations:^{
                    cv.panelView.transform = CGAffineTransformMakeTranslation(0, cv.panelView.bounds.size.height);
                    cv.backgroundView.alpha = 0;
                } completion:^(BOOL finished) {
                    [v removeFromSuperview];
                }];
            }
        }
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor clearColor];

    CGRect screen = self.bounds;

    // 背景
    _backgroundView = [[UIView alloc] initWithFrame:screen];
    _backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    _backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_backgroundView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackgroundTap:)];
    tap.delegate = self;
    [_backgroundView addGestureRecognizer:tap];

    // 面板
    CGFloat panelHeight = MIN(screen.size.height * 0.7, 520);
    CGRect panelFrame = CGRectMake(0, screen.size.height - panelHeight, screen.size.width, panelHeight);
    _panelView = [[UIView alloc] initWithFrame:panelFrame];
    _panelView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    _panelView.layer.cornerRadius = 16;
    _panelView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _panelView.layer.masksToBounds = YES;
    _panelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self addSubview:_panelView];

    // 标题
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, screen.size.width - 80, 30)];
    _titleLabel.text = @"YouTubili 弹幕设置";
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [_panelView addSubview:_titleLabel];

    // 关闭按钮
    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setTitle:@"完成" forState:UIControlStateNormal];
    [_closeButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _closeButton.frame = CGRectMake(screen.size.width - 80, 16, 64, 30);
    [_closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [_panelView addSubview:_closeButton];

    // TableView
    CGRect tableFrame = CGRectMake(0, 56, screen.size.width, panelHeight - 56);
    _tableView = [[UITableView alloc] initWithFrame:tableFrame style:UITableViewStyleGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.1];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panelView addSubview:_tableView];

    // 注册 cell
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SwitchCell"];
}

#pragma mark - Actions

- (void)onBackgroundTap:(UITapGestureRecognizer *)tap {
    [DanmakuControlView dismiss];
}

- (void)close {
    [DanmakuControlView dismiss];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1; // 开关
        case 1: return 4; // 显示设置
        case 2: return 3; // 类型设置
        case 3: return 2; // 高级
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"基本";
        case 1: return @"显示";
        case 2: return @"弹幕类型";
        case 3: return @"高级";
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 48;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SettingsManager *s = [SettingsManager shared];

    UITableViewCell *cell = nil;

    switch (indexPath.section) {
        case 0: {
            // 开关
            cell = [self switchCellWithText:@"启用弹幕" value:s.danmakuEnabled tag:100];
            break;
        }
        case 1: {
            // 显示设置
            switch (indexPath.row) {
                case 0: cell = [self sliderCellWithText:@"不透明度" value:s.opacity tag:200 min:0.2 max:1.0]; break;
                case 1: cell = [self sliderCellWithText:@"字体大小" value:s.fontScale tag:201 min:0.5 max:2.0]; break;
                case 2: cell = [self sliderCellWithText:@"滚动速度" value:s.speedScale tag:202 min:0.5 max:3.0]; break;
                case 3: cell = [self sliderCellWithText:@"显示区域" value:s.displayAreaRatio tag:203 min:0.3 max:1.0]; break;
            }
            break;
        }
        case 2: {
            // 类型设置
            switch (indexPath.row) {
                case 0: cell = [self switchCellWithText:@"滚动弹幕" value:s.showScrollDanmaku tag:300]; break;
                case 1: cell = [self switchCellWithText:@"顶部弹幕" value:s.showTopDanmaku tag:301]; break;
                case 2: cell = [self switchCellWithText:@"底部弹幕" value:s.showBottomDanmaku tag:302]; break;
            }
            break;
        }
        case 3: {
            // 高级
            switch (indexPath.row) {
                case 0: {
                    cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
                    cell.textLabel.text = @"Bilibili Cookie";
                    cell.detailTextLabel.text = s.biliCookie.length > 0 ? @"已设置" : @"未设置";
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
                    cell.textLabel.textColor = [UIColor whiteColor];
                    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
                    break;
                }
                case 1: {
                    cell = [self switchCellWithText:@"自动匹配 Bilibili 视频" value:s.autoMatch tag:400];
                    break;
                }
            }
            break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 3 && indexPath.row == 0) {
        [self showCookieEditor];
    }
}

#pragma mark - Cell 工厂方法

- (UITableViewCell *)switchCellWithText:(NSString *)text value:(BOOL)value tag:(NSInteger)tag {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SwitchCell"];
    cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    cell.textLabel.text = text;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = value;
    sw.tag = tag;
    [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;

    return cell;
}

- (UITableViewCell *)sliderCellWithText:(NSString *)text value:(float)value tag:(NSInteger)tag min:(float)min max:(float)max {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SliderCell"];
    cell.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    cell.textLabel.text = text;
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // 显示当前值
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", value];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];

    // 滑块
    CGRect sliderFrame = CGRectMake(cell.contentView.bounds.size.width - 200, 8, 180, 32);
    UISlider *slider = [[UISlider alloc] initWithFrame:sliderFrame];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.tag = tag;
    [slider addTarget:self action:@selector(onSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [cell.contentView addSubview:slider];

    // 自动布局
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addConstraints:@[
        [NSLayoutConstraint constraintWithItem:slider attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutAttributeEqual toItem:cell.contentView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
        [NSLayoutConstraint constraintWithItem:slider attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutAttributeEqual toItem:cell.contentView attribute:NSLayoutAttributeTrailing multiplier:1 constant:-16],
        [NSLayoutConstraint constraintWithItem:slider attribute:NSLayoutAttributeWidth relatedBy:NSLayoutAttributeEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:180],
    ]];

    // 让 detailTextLabel 不挡住 slider
    cell.detailTextLabel.frame = CGRectZero;

    return cell;
}

#pragma mark - 控件事件

- (void)onSwitchChanged:(UISwitch *)sw {
    SettingsManager *s = [SettingsManager shared];
    switch (sw.tag) {
        case 100: s.danmakuEnabled = sw.on; break;
        case 300: s.showScrollDanmaku = sw.on; break;
        case 301: s.showTopDanmaku = sw.on; break;
        case 302: s.showBottomDanmaku = sw.on; break;
        case 400: s.autoMatch = sw.on; break;
    }
    [s save];
}

- (void)onSliderChanged:(UISlider *)slider {
    SettingsManager *s = [SettingsManager shared];
    float value = slider.value;

    switch (slider.tag) {
        case 200: s.opacity = value; break;
        case 201: s.fontScale = value; break;
        case 202: s.speedScale = value; break;
        case 203: s.displayAreaRatio = value; break;
    }

    // 找到对应的 cell 更新显示
    NSIndexPath *path = nil;
    switch (slider.tag) {
        case 200: path = [NSIndexPath indexPathForRow:0 inSection:1]; break;
        case 201: path = [NSIndexPath indexPathForRow:1 inSection:1]; break;
        case 202: path = [NSIndexPath indexPathForRow:2 inSection:1]; break;
        case 203: path = [NSIndexPath indexPathForRow:3 inSection:1]; break;
    }
    if (path) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:path];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", value];
    }

    [s save];
}

#pragma mark - Cookie 编辑

- (void)showCookieEditor {
    SettingsManager *s = [SettingsManager shared];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Bilibili Cookie"
                                                                   message:@"粘贴你的 Bilibili Cookie（用于绕过风控，可选）"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = s.biliCookie;
        textField.placeholder = @"SESSDATA=xxx; bili_jct=xxx; ...";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        s.biliCookie = alert.textFields.firstObject.text ?: @"";
        [s save];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        s.biliCookie = @"";
        [s save];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *topVC = [self topViewController];
    [topVC presentViewController:alert animated:YES completion:nil];
}

- (UIViewController *)topViewController {
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (touch.view == _backgroundView) return YES;
    return NO;
}

@end
