//
//  STADocSetStore.m
//  Stash
//
//  Created by Tom Davie on 11/03/2013.
//
//

#import "STADocSetStore.h"
#import "STADocSetInternal.h"
#import "HTMLParser.h"

static const char *sta_queue_label(const char *label) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *fullLabel = [[bundle bundleIdentifier] stringByAppendingFormat:@".%s", label];
    return [fullLabel UTF8String];
}

@implementation STADocSetStore {
    NSURL *_cacheURL;
    NSMutableArray *_indexingDocsets;
    NSDictionary *_docSets;

    NSMutableSet *_locations;
    FSEventStreamRef _eventStream;
    dispatch_queue_t _scanQueue;
    dispatch_queue_t _indexQueue;
}

- (NSArray *)docSets {
    return [_docSets allValues];
}

- (instancetype)initWithCacheDirectory:(NSURL *)cacheURL {
    if (!(self = [super init]))
        return nil;

    NSParameterAssert(cacheURL != nil);

    _cacheURL = cacheURL;
    _scanQueue = dispatch_queue_create(sta_queue_label("docSetScanning"), DISPATCH_QUEUE_SERIAL);
    _indexQueue = dispatch_queue_create(sta_queue_label("docSetIndexing"), DISPATCH_QUEUE_SERIAL);
    _docSets = @{};
    _indexingDocsets = [NSMutableArray array];

    _locations = [NSMutableSet set];
    [self addStandardLocations];

    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

- (void)loadWithCompletionHandler:(void (^)(NSError *error))completionHandler {
    dispatch_async(_scanQueue, ^{
        _docSets = [self availableDocSets];
        for (STADocSet *docSet in [_docSets allValues]) {
            [self loadSymbolsForDocSet:docSet];
        }
        //[self startMonitoring];
        completionHandler(nil);
    });
}

- (void)loadSymbolsForDocSet:(STADocSet *)docSet {
    NSURL *indexURL = [[_cacheURL URLByAppendingPathComponent:docSet.identifier isDirectory:NO] URLByAppendingPathExtension:@"stashidx"];
    NSDictionary *cache = [NSDictionary dictionaryWithContentsOfURL:indexURL];
    if (cache) {
        // TODO: Only if version, URL, and date match
        [docSet loadSymbolsFromPropertyListRepresentation:cache];
    } else {
        [self indexDocSet:docSet completionHandler:^(NSError *error) {
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:[docSet propertyListRepresentation] format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
            if (error) {
                NSLog(@"Error serializing cache plist: %@", error);
            }
            [data writeToURL:indexURL atomically:YES];
        }];
    }
}

- (void)searchString:(NSString *)searchString method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler {
    return [self searchString:searchString inDocSets:self.docSets method:method completionHandler:completionHandler];
}

- (void)searchString:(NSString *)searchString inDocSets:(NSArray *)docSets method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler {
    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    NSMutableArray *results = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    for (STADocSet *docSet in docSets) {
        dispatch_group_async(group, queue, ^{
            [docSet search:searchString
                    method:method
                  onResult:^(STASymbol *symbol) {
                      OSSpinLockLock(&lock);
                      [results addObject:symbol];
                      OSSpinLockUnlock(&lock);
                  }];
        });
    }

    dispatch_group_notify(group, queue, ^{
        [results sortUsingSelector:@selector(compare:)];
        completionHandler(results);
    });
}

static NSComparator STADocSetComparator = ^(STADocSet *obj1, STADocSet *obj2) {
    NSComparisonResult result = [obj1.docSetVersion compare:obj2.docSetVersion options:NSNumericSearch];
    if (result == NSOrderedSame) {
        NSDate *date1, *date2;
        [obj1.URL getResourceValue:&date1 forKey:NSURLContentModificationDateKey error:nil];
        [obj2.URL getResourceValue:&date2 forKey:NSURLContentModificationDateKey error:nil];
        result = [date1 compare:date2];
    }

    return result;
};

/**
 * Returns the doc sets available on the system.
 *
 * If multiple doc sets with the same identifier exist, the doc set with the highest version number
 * or most recent modification date will be selected.
 */
- (NSDictionary *)availableDocSets {
    NSMutableDictionary *docSets = [NSMutableDictionary dictionary];

    for (NSURL *directory in _locations) {
        NSArray *directoryDocSets = [self docSetsAtURL:directory];

        for (STADocSet *docSet in directoryDocSets) {
            STADocSet *existingDocSet = _docSets[docSet.identifier];
            if (!existingDocSet || STADocSetComparator(existingDocSet, docSet) == NSOrderedAscending) {
                docSets[docSet.identifier] = docSet;
            }
        }
    }

    return docSets;
}

- (void)addStandardLocations {
    NSURL *libraryURL = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    if (libraryURL) {
        NSURL *sharedDocSetsURL = [libraryURL URLByAppendingPathComponent:@"Developer/Shared/Documentation/DocSets" isDirectory:YES];
        [_locations addObject:sharedDocSetsURL];
    }
}

- (void)checkForUpdatedDocSets {
    NSDictionary *currentDocSets = [self availableDocSets];
    if (![currentDocSets isEqual:_docSets]) {
    }
}

static void EventStreamCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
	STADocSetStore *self = (__bridge STADocSetStore *)clientCallBackInfo;
    [self checkForUpdatedDocSets];
    // TODO: Schedule, wait for period of idle time
}

- (void)startMonitoring {
    if (_eventStream) {
        [self stopMonitoring];
    }

    FSEventStreamContext streamContext = {};
	streamContext.info = (__bridge void *)self;

	NSMutableArray *folderPaths = [NSMutableArray array];
	for (NSURL *url in _locations) {
		[folderPaths addObject:[url path]];
	}

	_eventStream = FSEventStreamCreate(kCFAllocatorDefault,
									  &EventStreamCallback,
									  &streamContext,
									  (__bridge CFArrayRef)folderPaths,
									  kFSEventStreamEventIdSinceNow,
									  2.0,
									  kFSEventStreamCreateFlagUseCFTypes);
    FSEventStreamSetDispatchQueue(_eventStream, _scanQueue);
	FSEventStreamStart(_eventStream);
}

- (void)stopMonitoring {
    if (_eventStream) {
        FSEventStreamStop(_eventStream);
		FSEventStreamInvalidate(_eventStream);
		FSEventStreamRelease(_eventStream);
        _eventStream = NULL;
    }
}

- (NSArray *)docSetsAtURL:(NSURL *)directory {
    NSMutableArray *docSets = [NSMutableArray array];
    NSArray *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory
                                                  includingPropertiesForKeys:@[NSURLTypeIdentifierKey]
                                                                     options:0
                                                                       error:nil];

    for (NSURL *url in urls) {
        STADocSet *docSet = [STADocSet docSetWithURL:url];
        if (docSet) {
            [docSets addObject:docSet];
        }
    }

    return docSets;
}

- (NSArray *)allDocsets
{
    return [self.docSets arrayByAddingObjectsFromArray:_indexingDocsets];
}

#pragma mark - Indexing

- (void)indexDocSet:(STADocSet *)docSet completionHandler:(void (^)(NSError *error))completionHandler {
    dispatch_async(_indexQueue, ^{
        [self indexDocSet:docSet];
        completionHandler(nil);
    });
}

- (void)indexDocSet:(STADocSet *)docSet {
#ifdef DEBUG
    NSLog(@"Started indexing %@", docSet);
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
#endif

    NSMutableArray *htmlURLs = [NSMutableArray array];
    NSMutableArray *symbols = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:docSet.URL
                                                             includingPropertiesForKeys:@[NSURLNameKey,
                                                                                          NSURLTypeIdentifierKey,
                                                                                          NSURLIsRegularFileKey,
                                                                                          NSURLIsDirectoryKey]
                                                                                options:0
                                                                           errorHandler:^BOOL (NSURL *url, NSError *err) { return YES; }];

    for (NSURL *url in enumerator) {
        NSString *type = nil;
        [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:nil];
        if ([type isEqualToString:(NSString *)kUTTypeHTML]) {
            [htmlURLs addObject:url];
        }
    }

    for (NSURL *url in htmlURLs) {
        @autoreleasepool {
            NSError *parseError = nil;
            HTMLParser *parser = [[HTMLParser alloc] initWithContentsOfURL:url error:&parseError];
            if (parseError) {
                NSLog(@"Error parsing %@: %@", url, parseError);
                continue;
            }

            NSString *path = [url path];

            for (HTMLNode *anchor in [[parser body] findChildTags:@"a"]) {
                NSString *anchorName = [anchor getAttributeNamed:@"name"];
                if (!anchorName) {
                    continue;
                }

                NSScanner *scanner = [NSScanner scannerWithString:anchorName];
                NSString *apiName;
                NSString *dump;
                NSString *language;
                NSString *symbolType;
                NSString *parent;
                NSString *symbolName;

                BOOL success = [scanner scanString:@"//" intoString:&dump];
                if (!success) {
                    continue;
                }

                success = [scanner scanUpToString:@"/" intoString:&apiName];
                [scanner setScanLocation:[scanner scanLocation] + 1];
                if (!success) {
                    continue;
                }

                STASymbol *symbol = nil;
                if ([apiName isEqualToString:@"api"]) {
                    success = [scanner scanUpToString:@"/" intoString:&dump];
                    [scanner setScanLocation:[scanner scanLocation] + 1];
                    if (!success) {
                        continue;
                    }

                    [scanner scanUpToString:@"/" intoString:&symbolName];
                    NSString *fullPath = [path stringByAppendingFormat:@"#%@", anchorName];
                    NSURL *symbolURL = [NSURL URLWithString:fullPath];
                    if (!symbolURL) {
                        NSLog(@"Invalid URL created for symbol: %@ in %@", anchorName, path);
                        continue;
                    }

                    symbol = [[STASymbol alloc] initWithLanguageString:nil symbolTypeString:nil symbolName:symbolName url:symbolURL docSet:docSet];
                } else {
                    success = [scanner scanUpToString:@"/" intoString:&language];
                    [scanner setScanLocation:[scanner scanLocation] + 1];
                    if (!success || [language isEqualToString:@"doc"]) { continue; }
                    success = [scanner scanUpToString:@"/" intoString:&symbolType];
                    [scanner setScanLocation:[scanner scanLocation] + 1];
                    if (!success) {
                        continue;
                    }

                    [scanner scanUpToString:@"/" intoString:&parent];
                    NSString *fullPath = [path stringByAppendingFormat:@"#%@", anchorName];
                    if ([scanner scanLocation] < [anchorName length] - 1) {
                        [scanner setScanLocation:[scanner scanLocation] + 1];
                        [scanner scanUpToString:@"/" intoString:&symbolName];
                        NSURL *symbolURL = [NSURL URLWithString:fullPath];
                        if (!symbolURL) {
                            NSLog(@"Invalid URL created for symbol: %@ in %@", anchorName, path);
                            continue;
                        }

                        symbol = [[STASymbol alloc] initWithLanguageString:language symbolTypeString:symbolType symbolName:symbolName parentName:parent url:symbolURL docSet:docSet];
                    } else {
                        symbol = [[STASymbol alloc] initWithLanguageString:language symbolTypeString:symbolType symbolName:parent url:[NSURL URLWithString:fullPath] docSet:docSet];
                    }
                }

                if (!symbol)
                    continue;

                STASymbolType t = [symbol symbolType];
                if (t != STASymbolTypeBinding && t != STASymbolTypeTag) {
                    [symbols addObject:symbol];
                }
            }
        }
    }

    [docSet setSymbols:symbols];

#ifdef DEBUG
    NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"Indexing took: %.2f seconds", end - start);
#endif
}

@end
