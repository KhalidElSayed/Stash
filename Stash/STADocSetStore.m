//
//  STADocSetStore.m
//  Stash
//
//  Created by Tom Davie on 11/03/2013.
//
//

#import "STADocSetStore.h"
#import "STADocSetInternal.h"
#import <libxml/HTMLparser.h>

static NSString * const STAIndexExtension = @"stashidx";

static const char *sta_queue_label(const char *label) {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *fullLabel = [[bundle bundleIdentifier] stringByAppendingFormat:@".%s", label];
    return [fullLabel UTF8String];
}

@implementation STADocSetStore {
    NSURL *_cacheURL;
    NSDictionary *_docSets;

    NSMutableSet *_locations;
    FSEventStreamRef _eventStream;
    dispatch_queue_t _scanQueue;
    dispatch_queue_t _indexQueue;
    dispatch_queue_t _indexIOQueue;
    dispatch_source_t _timerSource;
    NSUInteger _indexingCount;
}

- (NSArray *)docSets {
    return [_docSets allValues];
}

- (instancetype)initWithCacheDirectory:(NSURL *)cacheURL delegate:(id<STADocSetStoreDelegate>)delegate delegateQueue:(dispatch_queue_t)queue {
    if (!(self = [super init]))
        return nil;

    NSParameterAssert(cacheURL != nil);

    _cacheURL = cacheURL;
    _delegate = delegate;
    _delegateQueue = queue ?: dispatch_get_main_queue();
    _scanQueue = dispatch_queue_create(sta_queue_label("docset-scanning"), DISPATCH_QUEUE_SERIAL);
    _indexQueue = dispatch_queue_create(sta_queue_label("docset-indexing"), DISPATCH_QUEUE_CONCURRENT);
    _indexIOQueue = dispatch_queue_create(sta_queue_label("docset-indexingio"), DISPATCH_QUEUE_SERIAL);
    _docSets = @{};

    _locations = [NSMutableSet set];
    [self addStandardLocations];

    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

- (void)loadWithCompletionHandler:(void (^)(NSError *error))completionHandler {
    dispatch_async(_scanQueue, ^{
        [self loadCachedDocSets];
        _loaded = YES;

        [self checkForUpdatedDocSets];
        [self startMonitoring];

        if (completionHandler) {
            completionHandler(nil);
        }
    });
}

- (void)loadCachedDocSets {
    NSMutableDictionary *docSets = [NSMutableDictionary dictionary];

    NSArray *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL
                                                  includingPropertiesForKeys:@[]
                                                                     options:0
                                                                       error:nil];

    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t sem = dispatch_semaphore_create(1);

    for (NSURL *url in urls) {
        if (![url.pathExtension isEqualToString:STAIndexExtension])
            continue;

        NSData *data = [NSData dataWithContentsOfURL:url];
        dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
            STADocSet *docSet = [STADocSet docSetWithPropertyListRepresentation:plist];
            if (docSet) {
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                docSets[docSet.identifier] = docSet;
                dispatch_semaphore_signal(sem);
            }
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    _docSets = docSets;

    if ([self.delegate respondsToSelector:@selector(docSetStoreDidUpdateDocSets:)]) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate docSetStoreDidUpdateDocSets:self];
        });
    }
}

/**
 * Removes cached indexes for doc sets that no longer exist.
 */
- (void)cleanCachedDocSets {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *urls = [fileManager contentsOfDirectoryAtURL:_cacheURL
                               includingPropertiesForKeys:@[]
                                                  options:0
                                                    error:nil];

    for (NSURL *url in urls) {
        if (![[url pathExtension] isEqualToString:STAIndexExtension])
            continue;

        NSString *identifier = [[url lastPathComponent] stringByDeletingPathExtension];

        if (_docSets[identifier] == nil) {
            [fileManager removeItemAtURL:url error:nil];
        }
    }
}

- (void)loadSymbolsForDocSet:(STADocSet *)docSet {
    if (docSet.symbols != nil)
        return;

    _indexingCount++;
    if (_indexingCount == 1) {
        _indexing = YES;
        if ([self.delegate respondsToSelector:@selector(docSetStoreWillBeginIndexing:)]) {
            dispatch_async(self.delegateQueue, ^{
                [self.delegate docSetStoreWillBeginIndexing:self];
            });
        }
    }

    dispatch_async(_indexIOQueue, ^{
        [self indexDocSet:docSet];

        NSError *error = nil;
        NSURL *indexURL = [[_cacheURL URLByAppendingPathComponent:docSet.identifier isDirectory:NO] URLByAppendingPathExtension:STAIndexExtension];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:[docSet propertyListRepresentation]
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&error];
        if (error) {
            NSLog(@"Error serializing cache plist: %@", error);
        } else {
            [data writeToURL:indexURL atomically:YES];
        }

        dispatch_async(_scanQueue, ^{
            _indexingCount--;
            if (_indexingCount == 0) {
                _indexing = NO;
                if ([self.delegate respondsToSelector:@selector(docSetStoreDidFinishIndexing:)]) {
                    dispatch_async(self.delegateQueue, ^{
                        [self.delegate docSetStoreDidFinishIndexing:self];
                    });
                }
            }
        });
    });

}

- (void)searchString:(NSString *)searchString method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler {
    return [self searchString:searchString inDocSets:self.docSets method:method completionHandler:completionHandler];
}

- (void)searchString:(NSString *)searchString inDocSets:(NSArray *)docSets method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler {
    __block OSSpinLock lock = OS_SPINLOCK_INIT;
    NSMutableArray *results = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

    if ([searchString length] < 1) {
        if (completionHandler) {
            completionHandler(results);
        }
        return;
    }

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
        if (completionHandler) {
            completionHandler(results);
        }
    });
}

static NSComparator STADocSetComparator = ^(STADocSet *obj1, STADocSet *obj2) {
    NSComparisonResult result = [obj1.docSetVersion compare:obj2.docSetVersion options:NSNumericSearch];
    if (result == NSOrderedSame) {
        result = [obj1.date compare:obj2.date];
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
            STADocSet *existingDocSet = docSets[docSet.identifier];
            if (!existingDocSet || STADocSetComparator(existingDocSet, docSet) == NSOrderedAscending) {
                // Use the already-loaded instance if equal
                STADocSet *loadedDocSet = _docSets[docSet.identifier];

                docSets[docSet.identifier] = [loadedDocSet isEqual:docSet] ? loadedDocSet : docSet;
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
    NSDictionary *availableDocSets = [self availableDocSets];
    if ([availableDocSets isEqual:_docSets])
        return;

    for (STADocSet *docSet in [availableDocSets allValues]) {
        [self loadSymbolsForDocSet:docSet];
    }

    _docSets = availableDocSets;

    if ([self.delegate respondsToSelector:@selector(docSetStoreDidUpdateDocSets:)]) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate docSetStoreDidUpdateDocSets:self];
        });
    }

    [self cleanCachedDocSets];
}

static void EventStreamCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[]) {
    STADocSetStore *self = (__bridge STADocSetStore *)clientCallBackInfo;
    dispatch_source_set_timer(self->_timerSource, dispatch_time(DISPATCH_TIME_NOW, 2ull * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 1ull * NSEC_PER_SEC);
}

- (void)startMonitoring {
    if (_eventStream) {
        [self stopMonitoring];
    }

    // Wait for a period of idle time before updating doc sets
    __weak STADocSetStore *weakSelf = self;
    _timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _scanQueue);
    dispatch_source_set_event_handler(_timerSource, ^{
        [weakSelf checkForUpdatedDocSets];
    });
    dispatch_resume(_timerSource);

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
                                       1.0,
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

        dispatch_source_cancel(_timerSource);
        _timerSource = nil;
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

#pragma mark - Indexing

/**
 * libxml2 callback used to extract anchor names from HTML documents.
 *
 * The attributes parameter is an array of name/value pairs terminated by a name
 * with a value of NULL.
 */
static void htmlStartElement(void *ctx, const char *name, const char **attributes) {
    if (!attributes || strcmp(name, "a") != 0)
        return;

    for (const char **attr = attributes; *attr != NULL; attr += 2) {
        if (strcmp(*attr, "name") == 0) {
            const char **value = attr + 1;
            if (value) {
                NSMutableArray *array = (__bridge NSMutableArray *)ctx;
                [array addObject:@(*value)];
            }
            break;
        }
    }
}

- (void)indexDocSet:(STADocSet *)docSet {
#ifdef DEBUG
    NSLog(@"Started indexing %@", docSet);
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
#endif

    __block NSUInteger index = 0;
    NSMutableArray *htmlURLs = [NSMutableArray array];
    NSMutableArray *symbols = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:docSet.URL
                                                             includingPropertiesForKeys:@[NSURLTypeIdentifierKey]
                                                                                options:0
                                                                           errorHandler:^BOOL (NSURL *url, NSError *err) { return YES; }];

    for (NSURL *url in enumerator) {
        NSString *type = nil;
        [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:nil];
        if (UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeHTML)) {
            [htmlURLs addObject:url];
        }
    }

    __block htmlSAXHandler handler = {};
    handler.startElement = (startElementSAXFunc)htmlStartElement;

    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t symbolsSemaphore = dispatch_semaphore_create(1);

    // Limit the number of concurrent jobs so we do not read in more data than we
    // can process and do not spawn many threads blocking on I/O.
    NSUInteger processorCount = [[NSProcessInfo processInfo] processorCount];
    dispatch_semaphore_t jobSemaphore = dispatch_semaphore_create(processorCount * 2);

    for (NSURL *url in htmlURLs) {
        @autoreleasepool {
            dispatch_semaphore_wait(jobSemaphore, DISPATCH_TIME_FOREVER);

            NSMutableArray *anchorNames = [NSMutableArray array];
            NSData *data = [NSData dataWithContentsOfURL:url];

            dispatch_group_async(group, _indexQueue, ^{
                @autoreleasepool {
                    htmlParserCtxtPtr context = htmlCreatePushParserCtxt(&handler, (__bridge void *)anchorNames, [data bytes], (int)[data length], NULL, XML_CHAR_ENCODING_UTF8);
                    htmlCtxtUseOptions(context, HTML_PARSE_RECOVER | HTML_PARSE_NONET);
                    htmlParseDocument(context);
                    htmlFreeParserCtxt(context);

                    index++;
                    double progress = ((double)index / (double)[htmlURLs count]) * 100.0;
                    [docSet setIndexingProgress:progress];
                    if ([self.delegate respondsToSelector:@selector(docSetStore:didReachIndexingProgress:forDocSet:)]) {
                        dispatch_async(self.delegateQueue, ^{
                            [self.delegate docSetStore:self didReachIndexingProgress:progress forDocSet:docSet];
                        });
                    }

                    for (NSString *anchorName in anchorNames) {
                        @autoreleasepool {
                            STASymbol *symbol = [self symbolForAnchorName:anchorName URL:url docSet:docSet];
                            if (!symbol)
                                continue;

                            STASymbolType t = [symbol symbolType];
                            if (t != STASymbolTypeBinding && t != STASymbolTypeTag) {
                                dispatch_semaphore_wait(symbolsSemaphore, DISPATCH_TIME_FOREVER);
                                [symbols addObject:symbol];
                                dispatch_semaphore_signal(symbolsSemaphore);
                            }
                        }
                    }

                    dispatch_semaphore_signal(jobSemaphore);
                }
            });
        }
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    [docSet setSymbols:symbols];

#ifdef DEBUG
    NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"Indexing took: %.2f seconds", end - start);
#endif
}

- (STASymbol *)symbolForAnchorName:(NSString *)anchorName URL:(NSURL *)url docSet:(STADocSet *)docSet {
    NSScanner *scanner = [NSScanner scannerWithString:anchorName];
    NSString *apiName;
    NSString *language;
    NSString *symbolType;
    NSString *symbolName;

    BOOL success = [scanner scanString:@"//" intoString:NULL];
    if (!success) {
        return nil;
    }

    success = [scanner scanUpToString:@"/" intoString:&apiName];
    [scanner setScanLocation:[scanner scanLocation] + 1];
    if (!success) {
        return nil;
    }

    STASymbol *symbol = nil;
    if ([apiName isEqualToString:@"api"]) {
        success = [scanner scanUpToString:@"/" intoString:NULL];
        [scanner setScanLocation:[scanner scanLocation] + 1];
        if (!success) {
            return nil;
        }

        [scanner scanUpToString:@"/" intoString:&symbolName];

        symbol = [[STASymbol alloc] initWithLanguageString:nil
                                          symbolTypeString:nil
                                                symbolName:symbolName
                                                       URL:url
                                                    anchor:anchorName
                                                    docSet:docSet];
    } else {
        success = [scanner scanUpToString:@"/" intoString:&language];
        [scanner setScanLocation:[scanner scanLocation] + 1];
        if (!success || [language isEqualToString:@"doc"]) {
            return nil;
        }

        success = [scanner scanUpToString:@"/" intoString:&symbolType];
        [scanner setScanLocation:[scanner scanLocation] + 1];
        if (!success) {
            return nil;
        }

        [scanner scanUpToString:@"/" intoString:&symbolName];
        if ([scanner scanLocation] < [anchorName length] - 1) {
            [scanner setScanLocation:[scanner scanLocation] + 1];
            [scanner scanUpToString:@"/" intoString:&symbolName];
        }

        symbol = [[STASymbol alloc] initWithLanguageString:language
                                          symbolTypeString:symbolType
                                                symbolName:symbolName
                                                       URL:url
                                                    anchor:anchorName
                                                    docSet:docSet];
    }

    return symbol;
}

@end
