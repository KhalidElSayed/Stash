#import "STADocSet.h"
#import "STAProgressReporter.h"

@protocol STADocSetIndexer <NSObject>

- (NSArray *)indexDocSet:(STADocSet *)docSet progressReporter:(STAProgressReporter *)progressReporter;

@end
