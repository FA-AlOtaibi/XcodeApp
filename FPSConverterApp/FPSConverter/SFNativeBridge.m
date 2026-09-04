#import "SFNativeBridge.h"
#import <sys/utsname.h>

@implementation SFNativeBridge

+ (BOOL)isModernLargeIPhone {
    CGSize s = UIScreen.mainScreen.bounds.size;
    CGFloat longEdge = MAX(s.width, s.height);
    return longEdge >= 852.0;
}

+ (NSString *)deviceSummary {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"%@ · iOS %@", machine, UIDevice.currentDevice.systemVersion];
}

+ (void)impactSuccess {
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g prepare];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}

+ (void)impactSelection {
    UISelectionFeedbackGenerator *g = [UISelectionFeedbackGenerator new];
    [g prepare];
    [g selectionChanged];
}

@end
