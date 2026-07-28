//
//  BiliAPI.h
//  YouTubiliDanmaku
//
//  Bilibili API 客户端
//  - 搜索视频
//  - 获取视频信息（BVID -> CID）
//  - 获取弹幕 XML（CID -> 弹幕列表）
//  - deflate-raw 解压缩
//

#import <Foundation/Foundation.h>
#import "DanmakuModel.h"

@interface BiliAPI : NSObject

+ (instancetype)shared;

/**
 * 搜索 Bilibili 视频
 * @param title 视频标题关键词
 * @param channel 频道/UP主名称（可选，用于精确匹配）
 * @param completion 回调，results 为搜索结果数组
 */
- (void)searchVideoWithTitle:(NSString *)title
                     channel:(NSString *)channel
                  completion:(void (^)(NSArray<BiliSearchResult *> *results, NSError *error))completion;

/**
 * 获取视频信息（BVID -> CID）
 * @param bvid BV 号
 * @param completion 回调，cid 为弹幕 CID
 */
- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                    completion:(void (^)(NSString *cid, NSString *title, NSTimeInterval duration, NSError *error))completion;

/**
 * 获取弹幕列表（CID -> 弹幕数组）
 * @param cid 弹幕 CID
 * @param completion 回调，danmakus 为弹幕数组
 */
- (void)fetchDanmakuWithCID:(NSString *)cid
                 completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion;

/**
 * 一步获取弹幕（BVID -> 弹幕数组）
 * 内部先获取 CID，再获取弹幕
 * @param bvid BV 号
 * @param completion 回调
 */
- (void)fetchDanmakuForBVID:(NSString *)bvid
                completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion;

/**
 * 设置 Cookie（用于绕过 Bilibili 风控）
 */
@property (nonatomic, copy) NSString *cookie;

@end
