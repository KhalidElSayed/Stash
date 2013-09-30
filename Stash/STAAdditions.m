#import "STAAdditions.h"

/**
 * Returns a dispatch queue label prefixed by the company portion of the application's bundle identifier.
 */
const char *sta_queue_label(const char *label) {
    static NSString *baseLabel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseLabel = [[[NSBundle mainBundle] bundleIdentifier] stringByDeletingPathExtension];
    });
    return [[baseLabel stringByAppendingFormat:@".%s", label] UTF8String];
}
