#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Rule calls use an independent Position; search runs on the caller's serial background queue.
@interface PikafishBridge : NSObject
+ (NSDictionary<NSString *, id> *)inspectFEN:(NSString *)fen
                                    moves:(NSArray<NSString *> *)moves
                                    hints:(BOOL)hints NS_SWIFT_NAME(inspect(fen:moves:hints:));
- (uint64_t)beginRequest;
- (void)stop;
- (NSDictionary<NSString *, id> *)searchFEN:(NSString *)fen
                                    moves:(NSArray<NSString *> *)moves
                              networkPath:(NSString *)networkPath
                             milliseconds:(NSInteger)milliseconds
                                    token:(uint64_t)token NS_SWIFT_NAME(search(fen:moves:networkPath:milliseconds:token:));
@end

NS_ASSUME_NONNULL_END
