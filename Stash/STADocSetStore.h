//
//  STADocSetStore.h
//  Stash
//
//  Created by Tom Davie on 11/03/2013.
//
//

#import <Foundation/Foundation.h>
#import "STADocSet.h"
@protocol STADocSetStoreDelegate;

@interface STADocSetStore : NSObject

@property (nonatomic, readonly) id<STADocSetStoreDelegate> delegate;
@property (nonatomic, readonly) dispatch_queue_t delegateQueue;
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;
@property (nonatomic, readonly, getter=isIndexing) BOOL indexing;
@property (nonatomic, readonly) NSArray *docSets;

- (instancetype)initWithCacheDirectory:(NSURL *)cacheURL delegate:(id<STADocSetStoreDelegate>)delegate delegateQueue:(dispatch_queue_t)queue;

- (void)loadWithCompletionHandler:(void (^)(NSError *error))completionHandler;

- (void)searchString:(NSString *)searchString method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler;
- (void)searchString:(NSString *)searchString inDocSets:(NSArray *)docSets method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler;

@end

@protocol STADocSetStoreDelegate <NSObject>
@optional

- (void)docSetStoreDidUpdateDocSets:(STADocSetStore *)docSetStore;
- (void)docSetStoreWillBeginIndexing:(STADocSetStore *)docSetStore;
- (void)docSetStore:(STADocSetStore *)docSetStore didReachIndexingProgress:(double)progress forDocSet:(STADocSet *)docSet;
- (void)docSetStoreDidFinishIndexing:(STADocSetStore *)docSetStore;

@end