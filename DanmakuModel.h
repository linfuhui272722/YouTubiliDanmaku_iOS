//
//  DanmakuModel.h
//  YouTubiliDanmaku
//
//  弹幕数据模型
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 * 单条弹幕数据
 * 对应 Bilibili 弹幕 XML 中 <d p="time,mode,fontSize,color,timestamp,pool,user,dmid">text</d>
 */
@interface Danmaku : NSObject

/** 出现时间（秒） */
@property (nonatomic, assign) NSTimeInterval time;

/** 弹幕类型: 1=滚动 4=底部 5=顶部 6=逆向 7=高级 8=代码 9=BAS */
@property (nonatomic, assign) int mode;

/** 字体大小（Bilibili 标准为 18 或 25） */
@property (nonatomic, assign) int fontSize;

/** 颜色值（十进制整数，如 16777215 = 0xFFFFFF = 白色） */
@property (nonatomic, assign) uint32_t color;

/** 弹幕 ID */
@property (nonatomic, copy) NSString *dmid;

/** 弹幕文本内容 */
@property (nonatomic, copy) NSString *text;

@end

/**
 * Bilibili 搜索结果
 */
@interface BiliSearchResult : NSObject

/** BV 号 */
@property (nonatomic, copy) NSString *bvid;

/** 视频标题（可能包含 HTML 高亮标签） */
@property (nonatomic, copy) NSString *title;

/** UP 主名称 */
@property (nonatomic, copy) NSString *author;

/** 封面 URL */
@property (nonatomic, copy) NSString *pic;

/** 视频时长（秒） */
@property (nonatomic, assign) NSTimeInterval duration;

@end
