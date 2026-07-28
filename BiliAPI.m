//
//  BiliAPI.m
//  YouTubiliDanmaku
//
//  Bilibili API 客户端实现 (基于 bilibili-API-collect 更新)
//

#import "BiliAPI.h"
#import <zlib.h>
#import <CommonCrypto/CommonDigest.h>

// Bilibili API 端点 (使用新版 WBI 接口)
static NSString *const kBiliSearchAPI = @"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=1&page_size=20";
static NSString *const kBiliViewAPI   = @"https://api.bilibili.com/x/web-interface/view?bvid=%@";
// 新版弹幕接口，需要 WBI 签名
static NSString *const kBiliDanmakuAPI = @"https://api.bilibili.com/x/v2/dm/wbi/web/seg.so?type=1&oid=%@&segment_index=1";

// 默认请求头
static NSString *const kUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1";
static NSString *const kReferer    = @"https://www.bilibili.com";

#pragma mark - BiliAPI 私有接口

@interface BiliAPI ()
@property (nonatomic, copy) NSString *buvid3;
// WBI 签名相关
@property (nonatomic, copy) NSString *imgKey;
@property (nonatomic, copy) NSString *subKey;
@property (nonatomic, strong) NSDate *keyUpdateTime;
// 私有方法声明
- (NSString *)generateBuvid3;
- (NSMutableURLRequest *)makeRequestWithURL:(NSString *)urlString;
- (NSString *)decodeHTML:(NSString *)s;
- (NSData *)gzipDecompress:(NSData *)compressed;
- (NSString *)cleanTitleForSearch:(NSString *)title channel:(NSString *)channel;
- (NSArray<Danmaku *> *)parseProtobufDanmaku:(NSData *)data;
- (NSArray<Danmaku *> *)parseXMLDanmaku:(NSData *)data;
- (Danmaku *)parseDanmakuElem:(NSData *)data;
- (NSUInteger)readVarint:(const uint8_t *)bytes pos:(NSUInteger *)pos length:(NSUInteger)length;
- (NSUInteger)skipField:(const uint8_t *)bytes pos:(NSUInteger)pos length:(NSUInteger)length wireType:(int)wireType;
// WBI 签名方法
- (void)refreshWBIKeysWithCompletion:(void (^)(BOOL success))completion;
- (NSString *)wbiSign:(NSDictionary *)params;
@end

#pragma mark - XML 解析器（旧版 XML 弹幕格式）

@interface BiliDanmakuXMLParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<Danmaku *> *results;
@property (nonatomic, strong) Danmaku *current;
@property (nonatomic, strong) NSMutableString *currentText;
@end

@implementation BiliDanmakuXMLParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _results = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
 attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    if ([elementName isEqualToString:@"d"]) {
        _current = [Danmaku new];
        _currentText = [NSMutableString string];

        NSString *p = attributeDict[@"p"];
        if (p) {
            NSArray *parts = [p componentsSeparatedByString:@","];
            if (parts.count >= 4) {
                _current.time     = [parts[0] doubleValue];
                _current.mode     = [parts[1] intValue];
                _current.fontSize = [parts[2] intValue];
                _current.color    = (uint32_t)[parts[3] longLongValue];
            }
            if (parts.count >= 8) {
                _current.dmid = parts[7];
            }
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (_currentText && string) {
        [_currentText appendString:string];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"d"]) {
        if (_current) {
            _current.text = [_currentText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (_current.text.length > 0) {
                [_results addObject:_current];
            }
            _current = nil;
            _currentText = nil;
        }
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    // 忽略解析错误
}

@end

#pragma mark - BiliAPI 实现

@implementation BiliAPI {
    NSString *_buvid3;
}

+ (instancetype)shared {
    static BiliAPI *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BiliAPI alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cookie = @"";
        _buvid3 = [self generateBuvid3];
        _imgKey = @"";
        _subKey = @"";
        _keyUpdateTime = [NSDate distantPast];
    }
    return self;
}

#pragma mark - 工具方法

- (NSString *)generateBuvid3 {
    NSMutableString *s = [NSMutableString string];
    NSArray *chars = @[@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",
                       @"A",@"B",@"C",@"D",@"E",@"F"];
    [s appendString:[chars objectAtIndex:arc4random_uniform(16)]];
    [s appendString:[chars objectAtIndex:arc4random_uniform(16)]];
    for (int i = 0; i < 33; i++) {
        [s appendString:[chars objectAtIndex:arc4random_uniform(16)]];
        if (i == 7 || i == 15 || i == 23) {
            [s appendString:@"-"];
        }
    }
    return s;
}

- (NSMutableURLRequest *)makeRequestWithURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:15.0];
    [request setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:kReferer forHTTPHeaderField:@"Referer"];
    [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [request setValue:@"zh-CN,zh;q=0.9" forHTTPHeaderField:@"Accept-Language"];
    [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];

    // Cookie
    NSString *cookie = self.cookie;
    if (cookie.length > 0) {
        [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    } else {
        [request setValue:[NSString stringWithFormat:@"buvid3=%@", _buvid3] forHTTPHeaderField:@"Cookie"];
    }

    return request;
}

- (NSString *)decodeHTML:(NSString *)s {
    if (!s) return @"";
    NSString *result = s;
    result = [result stringByReplacingOccurrencesOfString:@"<em class=\"keyword\">" withString:@""];
    result = [result stringByReplacingOccurrencesOfString:@"</em>" withString:@""];
    result = [result stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    result = [result stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    result = [result stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    result = [result stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    result = [result stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    return result;
}

/**
 * gzip 解压缩 (支持 raw deflate 和 gzip)
 * Bilibili 的 seg.so 接口返回的是 gzip 压缩的 protobuf 数据
 */
- (NSData *)gzipDecompress:(NSData *)compressed {
    if (!compressed || compressed.length == 0) return nil;

    // 检查是否是 gzip 格式 (0x1F 0x8B)
    BOOL isGzip = NO;
    if (compressed.length >= 2) {
        const uint8_t *bytes = compressed.bytes;
        if (bytes[0] == 0x1F && bytes[1] == 0x8B) {
            isGzip = YES;
        }
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)compressed.length;

    int windowBits = isGzip ? 16 + 15 : -15; // gzip 自动检测 或 raw deflate
    if (inflateInit2(&stream, windowBits) != Z_OK) {
        NSLog(@"[YouTubili] inflateInit2 failed");
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithCapacity:compressed.length * 5];
    uint8_t buffer[16384];

    while (YES) {
        stream.next_out = buffer;
        stream.avail_out = sizeof(buffer);

        int ret = inflate(&stream, Z_NO_FLUSH);
        if (ret == Z_STREAM_END || ret == Z_OK) {
            NSUInteger bytesWritten = sizeof(buffer) - stream.avail_out;
            if (bytesWritten > 0) {
                [output appendBytes:buffer length:bytesWritten];
            }
            if (ret == Z_STREAM_END) break;
        } else {
            NSLog(@"[YouTubili] inflate failed with code %d", ret);
            inflateEnd(&stream);
            return nil;
        }
        if (stream.avail_out > 0 && ret != Z_OK && ret != Z_STREAM_END) break;
    }

    inflateEnd(&stream);
    return output.length > 0 ? output : nil;
}

#pragma mark - WBI 签名 (参考 bilibili-API-collect)

- (void)refreshWBIKeysWithCompletion:(void (^)(BOOL success))completion {
    // 如果 key 在 10 分钟内更新过且有效，直接返回成功
    if (self.imgKey.length > 0 && self.subKey.length > 0 &&
        [[NSDate date] timeIntervalSinceDate:self.keyUpdateTime] < 600) {
        if (completion) completion(YES);
        return;
    }

    NSString *urlStr = @"https://api.bilibili.com/x/web-interface/nav";
    NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(NO);
            return;
        }

        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            if (completion) completion(NO);
            return;
        }

        NSDictionary *wbiImg = json[@"data"][@"wbi_img"];
        if (!wbiImg) {
            if (completion) completion(NO);
            return;
        }

        NSString *imgUrl = wbiImg[@"img_url"];
        NSString *subUrl = wbiImg[@"sub_url"];
        if (!imgUrl || !subUrl) {
            if (completion) completion(NO);
            return;
        }

        // 从 URL 中提取 key (文件名不含扩展名)
        self.imgKey = [[imgUrl lastPathComponent] stringByDeletingPathExtension];
        self.subKey = [[subUrl lastPathComponent] stringByDeletingPathExtension];
        self.keyUpdateTime = [NSDate date];

        NSLog(@"[YouTubili] WBI Keys refreshed: imgKey=%@, subKey=%@", self.imgKey, self.subKey);
        if (completion) completion(YES);
    }];

    [task resume];
}

- (NSString *)wbiSign:(NSDictionary *)params {
    if (self.imgKey.length == 0 || self.subKey.length == 0) {
        // 如果没有 key，返回空签名（部分接口可能不需要）
        return @"";
    }

    // 1. 拼接 imgKey + subKey
    NSString *mixKey = [NSString stringWithFormat:@"%@%@", self.imgKey, self.subKey];

    // 2. 参数按 key 排序
    NSArray *sortedKeys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *kvPairs = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        id value = params[key];
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
            [kvPairs addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }
    }

    // 3. 拼接参数字符串
    NSString *queryString = [kvPairs componentsJoinedByString:@"&"];

    // 4. 拼接 mixKey 并计算 MD5
    NSString *signString = [NSString stringWithFormat:@"%@%@", queryString, mixKey];
    const char *cStr = [signString UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);

    NSMutableString *md5 = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [md5 appendFormat:@"%02x", digest[i]];
    }

    return md5;
}

#pragma mark - 搜索视频

- (void)searchVideoWithTitle:(NSString *)title
                     channel:(NSString *)channel
                  completion:(void (^)(NSArray<BiliSearchResult *> *results, NSError *error))completion {
    // 清理标题
    NSString *keyword = [self cleanTitleForSearch:title channel:channel];

    NSString *encoded = [keyword stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:kBiliSearchAPI, encoded];

    NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

    NSLog(@"[YouTubili] Searching: %@", urlStr);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(@[], error);
            return;
        }

        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            if (completion) completion(@[], jsonError);
            return;
        }

        NSNumber *code = json[@"code"];
        if (![code isEqualToNumber:@0]) {
            NSString *msg = json[@"message"] ?: @"Bilibili API error";
            NSLog(@"[YouTubili] Search API error: %@ (%@)", msg, code);
            if (completion) completion(@[], [NSError errorWithDomain:@"BiliAPI" code:code.intValue userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }

        NSDictionary *dataDict = json[@"data"];
        NSArray *results = dataDict[@"result"];
        if (![results isKindOfClass:[NSArray class]]) {
            if (completion) completion(@[], nil);
            return;
        }

        NSMutableArray<BiliSearchResult *> *output = [NSMutableArray array];
        for (NSDictionary *item in results) {
            BiliSearchResult *r = [BiliSearchResult new];
            r.bvid = item[@"bvid"];
            r.title = [self decodeHTML:item[@"title"]];
            r.pic = item[@"pic"];

            NSDictionary *author = item[@"author"];
            if ([author isKindOfClass:[NSDictionary class]]) {
                r.author = author[@"name"];
            } else if ([author isKindOfClass:[NSString class]]) {
                r.author = author;
            }

            NSString *durationStr = item[@"duration"];
            if (durationStr) {
                NSArray *parts = [durationStr componentsSeparatedByString:@":"];
                NSTimeInterval dur = 0;
                for (NSString *p in parts) {
                    dur = dur * 60 + [p intValue];
                }
                r.duration = dur;
            }

            if (r.bvid.length > 0) {
                [output addObject:r];
            }
        }

        NSLog(@"[YouTubili] Found %lu results", (unsigned long)output.count);
        if (completion) completion(output, nil);
    }];

    [task resume];
}

- (NSString *)cleanTitleForSearch:(NSString *)title channel:(NSString *)channel {
    NSMutableString *s = [title mutableCopy];

    // 去除括号内容 - 修复：只去除括号及其内部内容，而不是截断后面所有字符
    NSArray *patterns = @[@[@"（", @"）"], @[@"(", @")"], @[@"【", @"】"], @[@"[", @"]"], @[@"「", @"」"]];
    for (NSArray *pair in patterns) {
        NSString *open = pair[0];
        NSString *close = pair[1];
        NSRange openRange = [s rangeOfString:open];
        if (openRange.location != NSNotFound) {
            NSRange closeRange = [s rangeOfString:close options:0 range:NSMakeRange(openRange.location, s.length - openRange.location)];
            if (closeRange.location != NSNotFound) {
                [s deleteCharactersInRange:NSMakeRange(openRange.location, closeRange.location - openRange.location + 1)];
            }
        }
    }

    // 去除常见后缀
    NSArray *suffixes = @[@" - YouTube", @" | YouTube", @" Official Video", @" MV", @" M/V", @" Official MV"];
    for (NSString *suffix in suffixes) {
        NSRange range = [s rangeOfString:suffix options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (range.location != NSNotFound && range.location + range.length == s.length) {
            [s deleteCharactersInRange:range];
        }
    }

    // 去除多余空格
    NSString *result = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // 合并多个空格
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    result = [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@" "];

    // 如果标题太短，加上频道名
    if (result.length < 3 && channel.length > 0) {
        result = [NSString stringWithFormat:@"%@ %@", channel, result];
    }

    return result;
}

#pragma mark - 获取视频信息

- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                    completion:(void (^)(NSString *cid, NSString *title, NSTimeInterval duration, NSString *token, NSError *error))completion {
    if (!bvid || bvid.length == 0) {
        if (completion) completion(nil, nil, 0, nil, [NSError errorWithDomain:@"BiliAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"BVID is empty"}]);
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:kBiliViewAPI, bvid];
    NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(nil, nil, 0, nil, error);
            return;
        }

        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            if (completion) completion(nil, nil, 0, nil, jsonError);
            return;
        }

        NSNumber *code = json[@"code"];
        if (![code isEqualToNumber:@0]) {
            NSString *msg = json[@"message"] ?: @"Bilibili API error";
            if (completion) completion(nil, nil, 0, nil, [NSError errorWithDomain:@"BiliAPI" code:code.intValue userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }

        NSDictionary *dataDict = json[@"data"];
        NSString *cid = [NSString stringWithFormat:@"%@", dataDict[@"cid"]];
        NSString *title = dataDict[@"title"];
        NSTimeInterval duration = [dataDict[@"duration"] doubleValue];
        NSString *token = dataDict[@"token"] ?: @""; // 从 view 接口获取 token

        NSLog(@"[YouTubili] Video info: cid=%@, title=%@, duration=%.0f, token=%@", cid, title, duration, token);

        if (completion) completion(cid, title, duration, token, nil);
    }];

    [task resume];
}

#pragma mark - 获取弹幕 (使用新版 WBI 接口)

- (void)fetchDanmakuWithCID:(NSString *)cid
                      token:(NSString *)token
                 completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion {
    if (!cid || cid.length == 0) {
        if (completion) completion(@[], [NSError errorWithDomain:@"BiliAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CID is empty"}]);
        return;
    }

    // 先刷新 WBI keys
    [self refreshWBIKeysWithCompletion:^(BOOL success) {
        // 构建基础参数
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        params[@"type"] = @"1";
        params[@"oid"] = cid;
        params[@"segment_index"] = @"1";
        if (token.length > 0) {
            params[@"token"] = token;
        }

        // 生成 WBI 签名
        NSString *wbiSign = [self wbiSign:params];
        if (wbiSign.length > 0) {
            params[@"w_rid"] = wbiSign;
            params[@"wts"] = @((long long)[[NSDate date] timeIntervalSince1970]);
        }

        // 构建 URL
        NSMutableString *urlStr = [NSMutableString stringWithString:kBiliDanmakuAPI];
        // 替换 oid 占位
        NSString *baseURL = [NSString stringWithFormat:kBiliDanmakuAPI, cid];
        urlStr = [NSMutableString stringWithString:baseURL];

        // 添加其他参数
        NSMutableArray *queryItems = [NSMutableArray array];
        for (NSString *key in params) {
            if ([key isEqualToString:@"oid"]) continue; // 已在 URL 中
            [queryItems addObject:[NSString stringWithFormat:@"%@=%@", key, params[key]]];
        }
        if (queryItems.count > 0) {
            [urlStr appendFormat:@"&%@", [queryItems componentsJoinedByString:@"&"]];
        }

        NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

        NSLog(@"[YouTubili] Fetching danmaku: %@", urlStr);

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completion) completion(@[], error);
                return;
            }

            // 检查是否是 JSON 错误响应
            if (data.length > 0) {
                NSString *preview = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(200, data.length))]
                                                         encoding:NSUTF8StringEncoding];
                if ([preview containsString:@"\"code\""] && [preview containsString:@"\"message\""]) {
                    NSError *jsonError;
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (!jsonError && json) {
                        NSNumber *code = json[@"code"];
                        if (![code isEqualToNumber:@0]) {
                            NSString *msg = json[@"message"] ?: @"Bilibili API error";
                            NSLog(@"[YouTubili] Danmaku API error: %@ (%@)", msg, code);
                            if (completion) completion(@[], [NSError errorWithDomain:@"BiliAPI" code:code.intValue userInfo:@{NSLocalizedDescriptionKey: msg}]);
                            return;
                        }
                    }
                }
            }

            // 尝试 gzip 解压 (新接口返回 gzip 压缩的 protobuf)
            NSData *decompressed = [self gzipDecompress:data];
            NSData *protobufData = decompressed ?: data;

            // 解析 protobuf
            NSArray<Danmaku *> *danmakus = [self parseProtobufDanmaku:protobufData];

            if (danmakus.count == 0) {
                // 尝试解析为 XML（旧版接口兼容）
                danmakus = [self parseXMLDanmaku:data];
            }

            NSLog(@"[YouTubili] Parsed %lu danmakus", (unsigned long)danmakus.count);
            if (completion) completion(danmakus, nil);
        }];

        [task resume];
    }];
}

#pragma mark - Protobuf 解析

- (NSArray<Danmaku *> *)parseProtobufDanmaku:(NSData *)data {
    NSMutableArray<Danmaku *> *results = [NSMutableArray array];

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger pos = 0;

    while (pos < length) {
        NSUInteger tag = [self readVarint:bytes pos:&pos length:length];
        int fieldNum = (int)(tag >> 3);
        int wireType = (int)(tag & 0x07);

        if (fieldNum == 1 && wireType == 2) {
            NSUInteger len = [self readVarint:bytes pos:&pos length:length];
            if (pos + len > length) break;

            NSData *elemData = [NSData dataWithBytes:bytes + pos length:len];
            Danmaku *d = [self parseDanmakuElem:elemData];
            if (d) {
                [results addObject:d];
            }
            pos += len;
        } else {
            pos = [self skipField:bytes pos:pos length:length wireType:wireType];
            if (pos == 0 || pos > length) break;
        }
    }

    return results;
}

- (Danmaku *)parseDanmakuElem:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger pos = 0;

    Danmaku *d = [Danmaku new];

    while (pos < length) {
        NSUInteger tag = [self readVarint:bytes pos:&pos length:length];
        int fieldNum = (int)(tag >> 3);
        int wireType = (int)(tag & 0x07);

        if (fieldNum == 2 && wireType == 0) {
            NSUInteger progress = [self readVarint:bytes pos:&pos length:length];
            d.time = progress / 1000.0;
        } else if (fieldNum == 3 && wireType == 0) {
            d.mode = (int)[self readVarint:bytes pos:&pos length:length];
        } else if (fieldNum == 4 && wireType == 0) {
            d.fontSize = (int)[self readVarint:bytes pos:&pos length:length];
        } else if (fieldNum == 5 && wireType == 0) {
            NSUInteger color = [self readVarint:bytes pos:&pos length:length];
            d.color = (uint32_t)color;
        } else if (fieldNum == 7 && wireType == 2) {
            NSUInteger len = [self readVarint:bytes pos:&pos length:length];
            if (pos + len <= length) {
                d.text = [[NSString alloc] initWithBytes:bytes + pos length:len encoding:NSUTF8StringEncoding];
            }
            pos += len;
        } else if (fieldNum == 12 && wireType == 2) {
            NSUInteger len = [self readVarint:bytes pos:&pos length:length];
            if (pos + len <= length) {
                d.dmid = [[NSString alloc] initWithBytes:bytes + pos length:len encoding:NSUTF8StringEncoding];
            }
            pos += len;
        } else {
            pos = [self skipField:bytes pos:pos length:length wireType:wireType];
            if (pos == 0 || pos > length) break;
        }
    }

    if (d.text.length == 0) return nil;
    return d;
}

- (NSUInteger)readVarint:(const uint8_t *)bytes pos:(NSUInteger *)pos length:(NSUInteger)length {
    NSUInteger result = 0;
    int shift = 0;
    while (*pos < length) {
        uint8_t b = bytes[*pos];
        (*pos)++;
        result |= ((NSUInteger)(b & 0x7F)) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
        if (shift >= 64) break;
    }
    return result;
}

- (NSUInteger)skipField:(const uint8_t *)bytes pos:(NSUInteger)pos length:(NSUInteger)length wireType:(int)wireType {
    switch (wireType) {
        case 0: {
            while (pos < length) {
                uint8_t b = bytes[pos++];
                if ((b & 0x80) == 0) return pos;
            }
            return 0;
        }
        case 1: {
            return pos + 8 <= length ? pos + 8 : 0;
        }
        case 2: {
            NSUInteger len = 0;
            NSUInteger p = pos;
            len = [self readVarint:bytes pos:&p length:length];
            return p + len <= length ? p + len : 0;
        }
        case 5: {
            return pos + 4 <= length ? pos + 4 : 0;
        }
        default:
            return 0;
    }
}

#pragma mark - XML 解析（旧版接口）

- (NSArray<Danmaku *> *)parseXMLDanmaku:(NSData *)data {
    NSString *preview = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(100, data.length))]
                                             encoding:NSUTF8StringEncoding];
    if (![preview containsString:@"<?xml"] && ![preview containsString:@"<i>"]) {
        return @[];
    }

    BiliDanmakuXMLParser *parser = [[BiliDanmakuXMLParser alloc] init];
    NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
    xmlParser.delegate = parser;
    [xmlParser parse];
    return parser.results;
}

#pragma mark - 一步获取弹幕 (使用新版 WBI 接口)

- (void)fetchDanmakuForBVID:(NSString *)bvid
                completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion {
    [self fetchVideoInfoWithBVID:bvid completion:^(NSString *cid, NSString *title, NSTimeInterval duration, NSString *token, NSError *error) {
        if (error || !cid) {
            if (completion) completion(@[], error);
            return;
        }
        [self fetchDanmakuWithCID:cid token:token completion:completion];
    }];
}

@end
