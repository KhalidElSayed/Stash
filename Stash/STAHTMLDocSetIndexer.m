#import "STAHTMLDocSetIndexer.h"
#import "STAAdditions.h"
#import <libxml/HTMLparser.h>

/**
 * Indexes a doc set by parsing its HTML documents for anchor names using the well-known [apple_ref format][1].
 *
 * [1]: http://developer.apple.com/library/Mac/#documentation/DeveloperTools/Conceptual/HeaderDoc/anchors/anchors.html
 */
@implementation STAHTMLDocSetIndexer {
    dispatch_queue_t _htmlQueue;
}

- (id)init {
    STASuperInit();

    _htmlQueue = dispatch_queue_create(sta_queue_label("html-indexing"), DISPATCH_QUEUE_CONCURRENT);

    return self;
}

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

- (NSArray *)indexDocSet:(STADocSet *)docSet progressReporter:(STAProgressReporter *)progressReporter {
    NSMutableArray *htmlURLs = [NSMutableArray array];
    NSMutableArray *symbols = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[docSet.URL filePathURL]
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

    progressReporter.totalUnits = [htmlURLs count];

    NSString *basePath = [docSet.URL path];

    __block int32_t index = 0;
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

            dispatch_group_async(group, _htmlQueue, ^{
                @autoreleasepool {
                    htmlParserCtxtPtr context = htmlCreatePushParserCtxt(&handler,
                                                                         (__bridge void *)anchorNames,
                                                                         [data bytes],
                                                                         (int)[data length],
                                                                         NULL,
                                                                         XML_CHAR_ENCODING_UTF8);
                    htmlCtxtUseOptions(context, HTML_PARSE_RECOVER | HTML_PARSE_NONET);
                    htmlParseDocument(context);
                    htmlFreeParserCtxt(context);

                    for (NSString *anchorName in anchorNames) {
                        @autoreleasepool {
                            NSString *relativePath = [[url path] substringFromIndex:[basePath length] + 1];
                            STASymbol *symbol = [self symbolForAnchorName:anchorName relativePathToDocSet:relativePath docSet:docSet];
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

                    progressReporter.completedUnits = OSAtomicIncrement32(&index);
                    dispatch_semaphore_signal(jobSemaphore);
                }
            });
        }
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    return symbols;
}

- (STASymbol *)symbolForAnchorName:(NSString *)anchorName relativePathToDocSet:(NSString *)relativePath docSet:(STADocSet *)docSet {
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
        // The appledoc project's anchor format, which does not contain any language or type information
        success = [scanner scanUpToString:@"/" intoString:NULL];
        [scanner setScanLocation:[scanner scanLocation] + 1];
        if (!success) {
            return nil;
        }

        [scanner scanUpToString:@"/" intoString:&symbolName];

        symbol = [[STASymbol alloc] initWithLanguage:STALanguageUnknown
                                          symbolType:STASymbolTypeUnknown
                                          symbolName:symbolName
                                relativePathToDocSet:relativePath
                                              anchor:anchorName
                                              docSet:docSet];
    } else {
        // The apple_ref anchor format used in Apple's documentation
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

        symbol = [[STASymbol alloc] initWithLanguage:STALanguageFromNSString(language)
                                          symbolType:STASymbolTypeFromNSString(symbolType)
                                          symbolName:symbolName
                                relativePathToDocSet:relativePath
                                              anchor:anchorName
                                              docSet:docSet];
    }

    return symbol;
}

@end
