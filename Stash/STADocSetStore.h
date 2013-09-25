//
//  STADocSetStore.h
//  Stash
//
//  Created by Tom Davie on 11/03/2013.
//
//

#import <Foundation/Foundation.h>
#import "STADocSet.h"

@interface STADocSetStore : NSObject

@property (nonatomic, readonly) NSArray *docSets;
@property (nonatomic, readonly) NSArray *indexingDocsets;
@property (nonatomic, readonly) NSArray *allDocsets;

- (instancetype)initWithCacheDirectory:(NSURL *)cacheURL;

- (void)loadWithCompletionHandler:(void (^)(NSError *error))completionHandler;

- (void)searchString:(NSString *)searchString method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler;
- (void)searchString:(NSString *)searchString inDocSets:(NSArray *)docSets method:(STASearchMethod)method completionHandler:(void(^)(NSArray *results))completionHandler;

@end
