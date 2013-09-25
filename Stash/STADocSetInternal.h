#import "STADocSet.h"

@interface STADocSet (STAInternal)

- (void)loadSymbolsFromPropertyListRepresentation:(id)plist;
- (void)setSymbols:(NSArray *)symbols;

- (void)search:(NSString *)searchString method:(STASearchMethod)method onResult:(void(^)(STASymbol *))result;

@end
