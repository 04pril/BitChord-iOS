#import <Foundation/Foundation.h>
@implementation NSBundle (BitChordProxyLocalization)
+ (NSBundle *)ytmu_defaultBundle {
    NSString *code = [NSUserDefaults.standardUserDefaults stringForKey:@"app_language_override"];
    NSString *path = code ? [NSBundle.mainBundle pathForResource:code ofType:@"lproj"] : nil;
    return path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
}
@end
