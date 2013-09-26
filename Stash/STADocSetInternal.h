#import "STADocSet.h"

@interface STADocSet (STAInternal)

@property (nonatomic) NSArray *symbols;

- (void)loadSymbolsFromPropertyListRepresentation:(id)plist;
- (void)setIndexingProgress:(double)progress;

- (void)search:(NSString *)searchString method:(STASearchMethod)method onResult:(void(^)(STASymbol *))result;

@end
