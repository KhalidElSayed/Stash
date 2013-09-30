#import "STAProgressReporter.h"
#import "STAAdditions.h"

@implementation STAProgressReporter {
    int32_t _totalUnits;
    int32_t _completedUnits;
    double _progress;
    double _lastReportedProgress;
    double _reportingGranularity;
    dispatch_queue_t _serialQueue;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue handler:(ProgressHandler)handler {
    STASuperInit();

    _serialQueue = dispatch_queue_create(sta_queue_label("progress-reporter"), DISPATCH_QUEUE_SERIAL);
    _queue = queue;
    _progressHandler = [handler copy];
    _reportingGranularity = 0.001;

    return self;
}

+ (instancetype)progressReporterWithQueue:(dispatch_queue_t)queue handler:(ProgressHandler)handler {
    return [[self alloc] initWithQueue:queue handler:handler];
}

- (BOOL)isIndeterminate {
    return (self.progress < 0);
}

- (int32_t)totalUnits {
    __block int32_t totalUnits;
    dispatch_sync(_serialQueue, ^{
        totalUnits = _totalUnits;
    });
    return totalUnits;
}

- (void)setTotalUnits:(int32_t)totalUnits {
    dispatch_async(_serialQueue, ^{
        _totalUnits = totalUnits;
        [self updateProgressLocked];
    });
}

- (int32_t)completedUnits {
    __block int32_t totalUnits;
    dispatch_sync(_serialQueue, ^{
        totalUnits = _totalUnits;
    });
    return totalUnits;
}

- (void)setCompletedUnits:(int32_t)completedUnits {
    dispatch_async(_serialQueue, ^{
        _completedUnits = completedUnits;
        [self updateProgressLocked];
    });
}

- (double)progress {
    __block double progress;
    dispatch_sync(_serialQueue, ^{
        progress = _progress;
    });
    return progress;
}

- (void)updateProgressLocked {
    double progress = (double)_completedUnits / (double)_totalUnits;
    if (_progress != progress) {
        _progress = progress;

        if (_queue && _progressHandler && (progress <= 0.0 || progress == 1.0 || fabs(progress - _lastReportedProgress) >= _reportingGranularity)) {
            _lastReportedProgress = progress;
            dispatch_async(_queue, ^{
                self.progressHandler(progress);
            });
        }
    }
}

@end
