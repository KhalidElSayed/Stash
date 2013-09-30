#import <Foundation/Foundation.h>

typedef void (^ProgressHandler)(double progress);

@interface STAProgressReporter : NSObject

@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) ProgressHandler progressHandler;
@property (nonatomic, readonly) double progress;
@property (nonatomic, readonly, getter=isIndeterminate) BOOL indeterminate;
@property (nonatomic) int32_t totalUnits;
@property (nonatomic) int32_t completedUnits;

+ (instancetype)progressReporterWithQueue:(dispatch_queue_t)queue handler:(ProgressHandler)handler;

@end
