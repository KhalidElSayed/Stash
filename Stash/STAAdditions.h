#import <Foundation/Foundation.h>

const char *sta_queue_label(const char *label);

#define STASuperInit() do { \
    if (!(self = [super init])) { \
        return nil; \
    } \
} while(0);
