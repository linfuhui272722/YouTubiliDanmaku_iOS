//
//  BiliAPI.m
//  YouTubiliDanmaku
//
//  Bilibili API 客户端实现
//

#import "BiliAPI.h"
#import <zlib.h>

// Bilibili API 端点
static NSString *const kBiliSearchAPI = @"https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=%@&page=1&page_size=20";
static NSString *const kBiliViewAPI   = @"https://api.bilibili.com/x/web-interface/view?bvid=%@";
static NSString *const kBiliDanmakuAPI = @"https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=%@&segment_index=1";

// 默认请求头
static NSString *const kUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1";
static NSString *const kReferer    = @"https://www.bilibili.com";

#pragma mark - BiliAPI 私有接口

@interface BiliAPI ()
// buvid3（Bilibili 风控标识）
@property (nonatomic, copy) NSString *buvid3;
// 私有方法声明
- (NSString *)generateBuvid3;
- (NSMutableURLRequest *)makeRequestWithURL:(NSString *)urlString;
- (NSString *)decodeHTML:(NSString *)s;
- (NSData *)deflateDecompress:(NSData *)compressed;
- (NSString *)cleanTitleForSearch:(NSString *)title channel:(NSString *)channel;
- (NSArray<Danmaku *> *)parseProtobufDanmaku:(NSData *)data;
- (NSArray<Danmaku *> *)parseXMLDanmaku:(NSData *)data;
- (Danmaku *)parseDanmakuElem:(NSData *)data;
- (NSUInteger)readVarint:(const uint8_t *)bytes pos:(NSUInteger *)pos length:(NSUInteger)length;
- (NSUInteger)skipField:(const uint8_t *)bytes pos:(NSUInteger)pos length:(NSUInteger)length wireType:(int)wireType;
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
    [request setValue:@"application/json, text/plain, */*", forHTTPHeaderField:@"Accept"];
    [request setValue:@"zh-CN,zh;q=0.9", forHTTPHeaderField:@"Accept-Language"];

    // Cookie
    NSString *cookie = self.cookie;
    if (cookie.length > 0) {
        [request setValue:cookie forHTTPHeaderField:@"Cookie"];
    } else {
        // 匿名访问也带上 buvid3
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
 * deflate-raw 解压缩
 * Bilibili 的 seg.so 接口返回的是 raw deflate 压缩的 protobuf 数据
 */
- (NSData *)deflateDecompress:(NSData *)compressed {
    if (!compressed || compressed.length == 0) return nil;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));

    stream.next_in = (Bytef *)compressed.bytes;
    stream.avail_in = (uInt)compressed.length;

    // windowBits = -15 表示 raw deflate（无 zlib 头）
    if (inflateInit2(&stream, -15) != Z_OK) {
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

#pragma mark - 搜索视频

- (void)searchVideoWithTitle:(NSString *)title
                     channel:(NSString *)channel
                  completion:(void (^)(NSArray<BiliSearchResult *> *results, NSError *error))completion {
    // 清理标题：去除括号内容、官方 MV 标记等
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

    // 去除括号内容
    NSArray *patterns = @[@"（", @"(", @"【", @"[", @"「"];
    for (NSString *p in patterns) {
        NSRange r = [s rangeOfString:p];
        if (r.location != NSNotFound) {
            [s deleteCharactersInRange:NSMakeRange(r.location, s.length - r.location)];
        }
    }

    // 去除常见后缀
    NSArray *suffixes = @[@" - YouTube", @" | YouTube", @" Official Video", @" MV", @" M/V", @" Official MV"];
    for (NSString *suffix in suffixes) {
        if ([s hasSuffix:suffix]) {
            [s deleteCharactersInRange:NSMakeRange(s.length - suffix.length, suffix.length)];
        }
    }

    // 去除 emoji 和特殊字符
    NSMutableString *cleaned = [NSMutableString string];
    for (NSInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 0x20 && c <= 0x7E) {
            [cleaned appendFormat:@"%C", c];
        } else if (c >= 0x4E00 && c <= 0x9FFF) {
            // CJK 统一汉字
            [cleaned appendFormat:@"%C", c];
        } else if (c >= 0x3040 && c <= 0x30FF) {
            // 平假名 + 片假名
            [cleaned appendFormat:@"%C", c];
        } else if (c >= 0xAC00 && c <= 0xD7AF) {
            // 韩文
            [cleaned appendFormat:@"%C", c];
        } else if (c == 0x20) {
            [cleaned appendFormat:@"%C", c];
        }
    }

    NSString *result = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    // 如果标题太短，加上频道名
    if (result.length < 3 && channel.length > 0) {
        result = [NSString stringWithFormat:@"%@ %@", channel, result];
    }

    return result;
}

#pragma mark - 获取视频信息

- (void)fetchVideoInfoWithBVID:(NSString *)bvid
                    completion:(void (^)(NSString *cid, NSString *title, NSTimeInterval duration, NSError *error))completion {
    if (!bvid || bvid.length == 0) {
        if (completion) completion(nil, nil, 0, [NSError errorWithDomain:@"BiliAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"BVID is empty"}]);
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:kBiliViewAPI, bvid];
    NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(nil, nil, 0, error);
            return;
        }

        NSError *jsonError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) {
            if (completion) completion(nil, nil, 0, jsonError);
            return;
        }

        NSNumber *code = json[@"code"];
        if (![code isEqualToNumber:@0]) {
            NSString *msg = json[@"message"] ?: @"Bilibili API error";
            if (completion) completion(nil, nil, 0, [NSError errorWithDomain:@"BiliAPI" code:code.intValue userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }

        NSDictionary *dataDict = json[@"data"];
        NSString *cid = [NSString stringWithFormat:@"%@", dataDict[@"cid"]];
        NSString *title = dataDict[@"title"];
        NSTimeInterval duration = [dataDict[@"duration"] doubleValue];

        NSLog(@"[YouTubili] Video info: cid=%@, title=%@, duration=%.0f", cid, title, duration);

        if (completion) completion(cid, title, duration, nil);
    }];

    [task resume];
}

#pragma mark - 获取弹幕

- (void)fetchDanmakuWithCID:(NSString *)cid
                 completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion {
    if (!cid || cid.length == 0) {
        if (completion) completion(@[], [NSError errorWithDomain:@"BiliAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"CID is empty"}]);
        return;
    }

    NSString *urlStr = [NSString stringWithFormat:kBiliDanmakuAPI, cid];
    NSMutableURLRequest *request = [self makeRequestWithURL:urlStr];

    NSLog(@"[YouTubili] Fetching danmaku: %@", urlStr);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(@[], error);
            return;
        }

        // 尝试直接解析为 protobuf（seg.so 接口可能未压缩）
        NSArray<Danmaku *> *danmakus = [self parseProtobufDanmaku:data];

        if (danmakus.count == 0) {
            // 尝试 deflate 解压后再解析 protobuf
            NSData *decompressed = [self deflateDecompress:data];
            if (decompressed) {
                danmakus = [self parseProtobufDanmaku:decompressed];
            }
        }

        if (danmakus.count == 0) {
            // 尝试解析为 XML（旧版接口）
            danmakus = [self parseXMLDanmaku:data];
        }

        NSLog(@"[YouTubili] Parsed %lu danmakus", (unsigned long)danmakus.count);
        if (completion) completion(danmakus, nil);
    }];

    [task resume];
}

#pragma mark - Protobuf 解析

/**
 * 解析 Bilibili 弹幕 protobuf 格式
 * 消息定义（简化）:
 * message DmSegMobileReply {
 *   repeated DanmakuElem elems = 1;
 * }
 * message DanmakuElem {
 *   int64 id = 1;
 *   int32 progress = 2;  // 毫秒
 *   int32 mode = 3;
 *   int32 fontsize = 4;
 *   uint32 color = 5;
 *   string midHash = 6;
 *   string content = 7;
 *   int64 ctime = 8;
 *   int32 weight = 9;
 *   string action = 10;
 *   int32 pool = 11;
 *   string idStr = 12;
 * }
 */
- (NSArray<Danmaku *> *)parseProtobufDanmaku:(NSData *)data {
    NSMutableArray<Danmaku *> *results = [NSMutableArray array];

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger pos = 0;

    while (pos < length) {
        // 读取字段号和 wire type
        NSUInteger tag = [self readVarint:bytes pos:&pos length:length];
        int fieldNum = (int)(tag >> 3);
        int wireType = (int)(tag & 0x07);

        if (fieldNum == 1 && wireType == 2) {
            // DanmakuElem 嵌套消息
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
            // progress (毫秒)
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
            // content
            NSUInteger len = [self readVarint:bytes pos:&pos length:length];
            if (pos + len <= length) {
                d.text = [[NSString alloc] initWithBytes:bytes + pos length:len encoding:NSUTF8StringEncoding];
            }
            pos += len;
        } else if (fieldNum == 12 && wireType == 2) {
            // idStr
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
        case 0: { // Varint
            while (pos < length) {
                uint8_t b = bytes[pos++];
                if ((b & 0x80) == 0) return pos;
            }
            return 0;
        }
        case 1: { // 64-bit
            return pos + 8 <= length ? pos + 8 : 0;
        }
        case 2: { // Length-delimited
            NSUInteger len = 0;
            NSUInteger p = pos;
            len = [self readVarint:bytes pos:&p length:length];
            return p + len <= length ? p + len : 0;
        }
        case 5: { // 32-bit
            return pos + 4 <= length ? pos + 4 : 0;
        }
        default:
            return 0;
    }
}

#pragma mark - XML 解析（旧版接口）

- (NSArray<Danmaku *> *)parseXMLDanmaku:(NSData *)data {
    // 检查是否是 XML
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

#pragma mark - 一步获取弹幕

- (void)fetchDanmakuForBVID:(NSString *)bvid
                completion:(void (^)(NSArray<Danmaku *> *danmakus, NSError *error))completion {
    [self fetchVideoInfoWithBVID:bvid completion:^(NSString *cid, NSString *title, NSTimeInterval duration, NSError *error) {
        if (error || !cid) {
            if (completion) completion(@[], error);
            return;
        }
        [self fetchDanmakuWithCID:cid completion:completion];
    }];
}

@end
