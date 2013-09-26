//
//  STADocSet.h
//  Stash
//
//  Created by Thomas Davie on 01/06/2012.
//  Copyright (c) 2012 Hunted Cow Studios. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "STASymbol.h"

typedef enum
{
    STAPlatformUnknown = 0,
    STAPlatformMacOS   = 1,
    STAPlatformIOS     = 2,
} STAPlatform;

@interface STADocSet : NSObject

@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly) NSDate *date;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *docSetVersion;
@property (nonatomic, readonly) STAPlatform platform;
@property (nonatomic, readonly) NSString *platformVersion;
@property (nonatomic, readonly) double indexingProgress;

+ (instancetype)docSetWithURL:(NSURL *)url;
+ (instancetype)docSetWithPropertyListRepresentation:(id)plist;

- (id)propertyListRepresentation;

@end
