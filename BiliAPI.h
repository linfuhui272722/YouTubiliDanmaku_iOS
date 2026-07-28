//
//  BiliAPI.h
//  YouTubiliDanmaku
//
//  Bilibili API 客户端
//  - 搜索视频
//  - 获取视频信息（BVID -> CID + token）
//  - 获取弹幕（CID + token -> 弹幕列表）
//  - gzip 解压缩
//

#import <Foundation/Foundation.h>
#import "DanmakuModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface BiliAPI : NSObject

+ (instancetype)shared;

/**
 * 搜索 Bilibili 视频
 * @param title 视频标题关键词
 * @param channel 频道/UP主名称（可选，用于精确匹配）
 * @param completion 回调，results 为搜索结果数组
 */
- (void)searchVideoWithTitle:(NSString *)title
                     channel:(nullable NSString *)channel
                  completion:(void (^)(NSArray<BiliSearchResult *> *results, NSError * _Nullable error))completion;

/**
 * 获取视频信息（BVID -> CID, token）
 * @param bvid BV 号
 * @param completion 回调，cid 为弹幕 CID，token 为弹幕接口所需 token
 */
- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                    completion:(void (^)(NSString * _Nullable cid, NSString * _Nullable title, NSTimeInterval duration, NSString * _Nullable token, NSError * _Nullable error))completion;

/**
 * 获取弹幕列表（CID + token -> 弹幕数组）
 * @param cid 弹幕 CID
 * @param token 从 view 接口获取的 token
 * @param completion 回调，danmakus 为弹幕数组
 */
- (void)fetchDanmakuWithCID:(NSString *)cid
                      token:(NSString *)token
                 completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError * _Nullable error))completion;

/**
 * 一步获取弹幕（BVID -> 弹幕数组）
 * 内部先获取 CID 和 token，再获取弹幕
 * @param bvid BV 号
 * @param completion 回调
 */
- (void)fetchDanmakuForBVID:(NSString *)bvid
                completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError * _Nullable error))completion;

/**
 * 设置 Cookie（用于绕过 Bilibili 风控，建议包含 DedeUserID 和 bili_jct）
 */
@property (nonatomic, copy) NSString *cookie;

@end

NS_ASSUME_NONNULL_END
