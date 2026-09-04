#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SFNativeBridge : NSObject
+ (BOOL)isModernLargeIPhone;
+ (NSString *)deviceSummary;
+ (void)impactSuccess;
+ (void)impactSelection;
@end

NS_ASSUME_NONNULL_END
