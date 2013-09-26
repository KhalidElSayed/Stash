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

static unsigned int STAPlistVersion = 1;
static NSString * const STAPlistVersionKey = @"plistVersion";
static NSString * const STAURLKey = @"URL";
static NSString * const STADateKey = @"date";
static NSString * const STAIdentifierKey = @"identifier";
static NSString * const STANameKey = @"name";
static NSString * const STADocSetVersionKey = @"docSetVersion";
static NSString * const STAPlatformKey = @"platform";
static NSString * const STAPlatformVersionKey = @"platformVersion";
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

    NSDate *date = nil;
    [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
    if (date) {
        _date = date;
    }

    return self;
}

- (instancetype)initWithPropertyListRepresentation:(id)plist {
    if (!(self = [super init]))
        return nil;

    if ([plist isKindOfClass:[NSDictionary class]] == NO)
        return nil;

    if ([plist[STAPlistVersionKey] unsignedIntValue] != STAPlistVersion)
        return nil;

    _URL = [NSURL URLByResolvingBookmarkData:plist[STAURLKey] options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:nil];
    _date = plist[STADateKey];
    _identifier = plist[STAIdentifierKey];
    _name = plist[STANameKey];
    _docSetVersion = plist[STADocSetVersionKey];
    _platform = [plist[STAPlatformKey] intValue];
    _platformVersion = plist[STAPlatformVersionKey];

    [self loadSymbolsFromPropertyListRepresentation:plist];

    return self;
}

- (id)propertyListRepresentation {
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    plist[STAPlistVersionKey] = @(STAPlistVersion);
    plist[STAURLKey] = [_URL bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
    plist[STADateKey] = _date;
    plist[STAIdentifierKey] = _identifier;
    plist[STANameKey] = _name;
    plist[STAPlatformKey] = @(_platform);

    if (_docSetVersion) {
        plist[STADocSetVersionKey] = _docSetVersion;
    }

    if (_platformVersion) {
        plist[STAPlatformVersionKey] = _platformVersion;
    }

    if (_symbols) {
        NSMutableArray *plistSymbols = [NSMutableArray arrayWithCapacity:[_symbols count]];
        for (STASymbol *symbol in _symbols) {
            [plistSymbols addObject:[symbol propertyListRepresentation]];
        }
        plist[STASymbolsKey] = plistSymbols;
    }

    return plist;
}

+ (instancetype)docSetWithURL:(NSURL *)url {
    return [[self alloc] initWithURL:url];
}

+ (instancetype)docSetWithPropertyListRepresentation:(id)plist {
    return [[self alloc] initWithPropertyListRepresentation:plist];
}

- (void)loadSymbolsFromPropertyListRepresentation:(id)plist {
    NSArray *plistSymbols = plist[STASymbolsKey];
    NSMutableArray *symbols = [NSMutableArray arrayWithCapacity:[plistSymbols count]];
    for (id plistSymbol in plistSymbols) {
        [symbols addObject:[[STASymbol alloc] initWithPropertyListRepresentation:plistSymbol docSet:self]];
    }
    [self setSymbols:symbols];
}

- (NSArray *)symbols {
    return _symbols;
}

- (void)setSymbols:(NSArray *)symbols {
    _symbols = symbols;
    [self setIndexingProgress:100.0];
}

- (void)setIndexingProgress:(double)progress {
    _indexingProgress = progress;
}

- (void)search:(NSString *)searchString method:(STASearchMethod)method onResult:(void(^)(STASymbol *))result
{
    if (!_symbols)
        return;

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
    return [self.identifier hash] ^ [self.docSetVersion hash] ^ [self.date hash];
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[STADocSet class]])
        return NO;

    return [[self identifier] isEqualToString:[object identifier]] &&
           [[self docSetVersion] isEqualToString:[object docSetVersion]] &&
           [[self date] isEqualTo:[object date]];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ (%@)", self.name, self.identifier];
}

@end
