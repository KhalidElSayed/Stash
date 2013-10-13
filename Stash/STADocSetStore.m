//
//  STADocSetStore.m
//  Stash
//
//  Created by Tom Davie on 11/03/2013.
//
//

#import "STADocSetStore.h"
#import "STADocSetInternal.h"
#import "STADatabaseDocSetIndexer.h"
#import "STAHTMLDocSetIndexer.h"
#import "STAAdditions.h"

static NSString * const STAIndexExtension = @"stashidx";

@implementation STADocSetStore {
    NSURL *_cacheURL;
    NSDictionary *_docSets;

    NSMutableSet *_locations;
    FSEventStreamRef _eventStream;

    /**
     * Paths to watch for file system changes.
     *
     * This may differ from _locations if any doc sets are included via
     * symbolic links, as FSEvents does not watch for changes through symlinks.
     */
    NSSet *_pathsToWatch;

    dispatch_queue_t _scanQueue;
    dispatch_queue_t _indexQueue;
    dispatch_source_t _timerSource;
    NSUInteger _indexingCount;

    /**
     * The list of doc set indexers in order of preference.
     */
    NSArray *_indexers;
}

- (NSArray *)docSets {
    return [_docSets allValues];
}

- (instancetype)initWithCacheDirectory:(NSURL *)cacheURL delegate:(id<STADocSetStoreDelegate>)delegate delegateQueue:(dispatch_queue_t)queue {
    STASuperInit();

    NSParameterAssert(cacheURL != nil);

    _cacheURL = cacheURL;
    _delegate = delegate;
    _delegateQueue = queue ?: dispatch_get_main_queue();
    _scanQueue = dispatch_queue_create(sta_queue_label("docset-scanning"), DISPATCH_QUEUE_SERIAL);
    _indexQueue = dispatch_queue_create(sta_queue_label("docset-indexing"), DISPATCH_QUEUE_SERIAL);
    _docSets = @{};
    _pathsToWatch = [NSSet set];

    _indexers = @[
        [STADatabaseDocSetIndexer new],
        [STAHTMLDocSetIndexer new]
    ];

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
        [self checkForUpdatedPathsToWatch];

        if (completionHandler) {
            completionHandler(nil);
        }
    });
}

- (void)loadCachedDocSets {
    NSMutableDictionary *docSets = [NSMutableDictionary dictionary];

    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t sem = dispatch_semaphore_create(1);

    for (NSURL *url in [self cachedDocSetURLs]) {
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
    for (NSURL *url in [self cachedDocSetURLs]) {
        NSString *identifier = [[url lastPathComponent] stringByDeletingPathExtension];

        if (_docSets[identifier] == nil) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }
    }
}

- (NSArray *)cachedDocSetURLs {
    NSArray *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL
                                                  includingPropertiesForKeys:@[]
                                                                     options:0
                                                                       error:nil];

    return [urls objectsAtIndexes:[urls indexesOfObjectsPassingTest:^BOOL(NSURL *url, NSUInteger idx, BOOL *stop) {
        return [url.pathExtension isEqualToString:STAIndexExtension];
    }]];
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

    dispatch_async(_indexQueue, ^{
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

    [self checkForUpdatedPathsToWatch];
    [self cleanCachedDocSets];
}

- (void)checkForUpdatedPathsToWatch {
    NSMutableSet *pathsToWatch = [NSMutableSet set];
    for (NSURL *url in _locations) {
        [pathsToWatch addObject:[url path]];
    }

    // FSEvents does not monitor through symbolic links so add the containing path for each
    // doc set as well to cover doc sets included via symlink.
    for (STADocSet *docSet in self.docSets) {
        NSString *path = [[docSet.URL path] stringByDeletingLastPathComponent];
        [pathsToWatch addObject:path];
    }

    if ([pathsToWatch isEqual:_pathsToWatch] == NO) {
        _pathsToWatch = pathsToWatch;
        [self stopMonitoring];
        [self startMonitoring];
    }
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

    _eventStream = FSEventStreamCreate(kCFAllocatorDefault,
                                       &EventStreamCallback,
                                       &streamContext,
                                       (__bridge CFArrayRef)[_pathsToWatch allObjects],
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
        STADocSet *docSet = [STADocSet docSetWithURL:[url URLByResolvingSymlinksInPath]];
        if (docSet) {
            [docSets addObject:docSet];
        }
    }

    return docSets;
}

#pragma mark - Indexing

- (void)indexDocSet:(STADocSet *)docSet {
    if ([self.delegate respondsToSelector:@selector(docSetStore:willBeginIndexingDocSet:)]) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate docSetStore:self willBeginIndexingDocSet:docSet];
        });
    }

#ifdef DEBUG
    NSLog(@"Started indexing %@", docSet);
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
#endif

    STAProgressReporter *progressReporter = nil;
    if ([self.delegate respondsToSelector:@selector(docSetStore:didReachIndexingProgress:forDocSet:)]) {
        progressReporter = [STAProgressReporter progressReporterWithQueue:self.delegateQueue handler:^(double progress) {
            docSet.indexingProgress = progress * 100.0;
            [self.delegate docSetStore:self didReachIndexingProgress:progress forDocSet:docSet];
        }];
    }

    for (id<STADocSetIndexer> indexer in _indexers) {
        NSArray *symbols = [indexer indexDocSet:docSet progressReporter:progressReporter];
        if (symbols) {
            [docSet setSymbols:symbols];
            break;
        }
    }

#ifdef DEBUG
    NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate];
    NSLog(@"Indexing took: %.2f seconds", end - start);
#endif

    if ([self.delegate respondsToSelector:@selector(docSetStore:didFinishIndexingDocSet:)]) {
        dispatch_async(self.delegateQueue, ^{
            [self.delegate docSetStore:self didFinishIndexingDocSet:docSet];
        });
    }
}

@end
