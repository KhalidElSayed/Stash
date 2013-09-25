//
//  STADocSet.m
//  Stash
//
//  Created by Thomas Davie on 01/06/2012.
//  Copyright (c) 2012 Hunted Cow Studios. All rights reserved.
//

#import "STADocSet.h"
#import "STADocSetInternal.h"

static NSString * const STADocSetUTI = @"com.apple.xcode.docset";
static NSString * const STASymbolsKey = @"symbols";

@implementation STADocSet {
    NSArray *_symbols;
}

- (instancetype)initWithURL:(NSURL *)url {
    if (!(self = [super init]))
        return nil;

    NSString *uti = nil;
    [url getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:nil];
    if (![uti isEqualToString:STADocSetUTI])
        return nil;

    NSBundle *bundle = [NSBundle bundleWithURL:url];
    if (!bundle)
        return nil;

    NSDictionary *info = [bundle infoDictionary];
    _URL = url;
    _identifier = [bundle bundleIdentifier];
    _name = info[@"CFBundleName"];
    _docSetVersion = info[@"CFBundleVersion"];
    _platformVersion = info[@"DocSetPlatformVersion"];

    NSString *platform = info[@"DocSetPlatformFamily"];
    if ([platform isEqualToString:@"iphoneos"]) {
        _platform = STAPlatformIOS;
    } else if ([platform isEqualToString:@"macosx"]) {
        _platform = STAPlatformMacOS;
    }

    _symbols = @[];

    return self;
}

+ (instancetype)docSetWithURL:(NSURL *)url {
    return [[self alloc] initWithURL:url];
}

- (void)loadSymbolsFromPropertyListRepresentation:(id)plist {
    NSArray *plistSymbols = plist[STASymbolsKey];
    NSMutableArray *symbols = [NSMutableArray arrayWithCapacity:[plistSymbols count]];
    for (id plistSymbol in plistSymbols) {
        [symbols addObject:[[STASymbol alloc] initWithPropertyListRepresentation:plistSymbol docSet:self]];
    }
    _symbols = symbols;
}

- (void)setSymbols:(NSArray *)symbols {
    _symbols = symbols;
}

- (id)propertyListRepresentation {
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    NSMutableArray *plistSymbols = [NSMutableArray arrayWithCapacity:[_symbols count]];
    for (STASymbol *symbol in _symbols) {
        [plistSymbols addObject:[symbol propertyListRepresentation]];
    }
    plist[STASymbolsKey] = plistSymbols;
    return plist;
}

- (void)search:(NSString *)searchString method:(STASearchMethod)method onResult:(void(^)(STASymbol *))result
{
#ifdef DEBUG
    NSDate *start = [NSDate date];
#endif

    [_symbols enumerateObjectsWithOptions:NSEnumerationConcurrent
                                     usingBlock:^(STASymbol *s,
                                                  NSUInteger idx,
                                                  BOOL *stop)
     {
         if ([s matches:searchString method:method])
         {
             result(s);
         }
     }];

#ifdef DEBUG
    NSTimeInterval timeInterval = [start timeIntervalSinceNow];
    DLog(@"Enumeration time (D:%@,Q:%@) %lf", self.name, searchString, -timeInterval);
#endif
}

- (void)unload
{
    [self setSymbols:[NSMutableArray array]];
}

- (NSUInteger)hash
{
    return [[self identifier] hash] & [[self docSetVersion] hash];
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[STADocSet class]])
        return NO;

    return [[self identifier] isEqualToString:[object identifier]] && [[self docSetVersion] isEqualToString:[object docSetVersion]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ (%@)", self.name, self.identifier];
}

@end
