//
//  STASymbol.m
//  Stash
//
//  Created by Thomas Davie on 02/06/2012.
//  Copyright (c) 2012 Hunted Cow Studios. All rights reserved.
//

#import "STASymbol.h"

#import "STADocSet.h"

NSUInteger STASymbolTypeOrder(STASymbolType type);

static NSString * const STALanguageKey = @"language";
static NSString * const STATypeKey = @"type";
static NSString * const STANameKey = @"name";
static NSString * const STARelativePathKey = @"relativePath";
static NSString * const STAAnchorKey = @"anchor";

@implementation STASymbol {
    NSString *_relativePath;
    NSString *_anchor;
}

- (instancetype)initWithLanguageString:(NSString *)language symbolTypeString:(NSString *)symbolType symbolName:(NSString *)symbolName URL:(NSURL *)fileURL anchor:(NSString *)anchor docSet:(STADocSet *)docSet {
    if (!(self = [super init]))
        return nil;

    NSParameterAssert(fileURL != nil);
    NSParameterAssert(docSet != nil);
    
    [self setLanguage:STALanguageFromNSString(language)];
    [self setSymbolType:STASymbolTypeFromNSString(symbolType)];
    [self setSymbolName:symbolName];
    [self setDocSet:docSet];

    // Store as a relative path so bookmark data does not need to be stored for every symbol
    NSString *basePath = [_docSet.URL path];
    _relativePath = [[fileURL path] substringFromIndex:[basePath length] + 1];
    _anchor = anchor;

    return self;
}

- (instancetype)initWithPropertyListRepresentation:(id)plist docSet:(STADocSet *)docSet {
    if (!(self = [super init]))
        return nil;

    _language = [plist[STALanguageKey] intValue];
    _symbolType = [plist[STATypeKey] intValue];
    _symbolName = plist[STANameKey];
    _relativePath = plist[STARelativePathKey];
    _anchor = plist[STAAnchorKey];
    _docSet = docSet;

    return self;
}

- (id)propertyListRepresentation {
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithDictionary:@{
        STALanguageKey: @(_language),
        STATypeKey: @(_symbolType),
        STANameKey: _symbolName,
        STARelativePathKey: _relativePath
    }];

    if (_anchor) {
        plist[STAAnchorKey] = _anchor;
    }

    return plist;
}

- (NSURL *)URL {
    if (_anchor) {
        NSString *anchor = CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)_anchor, NULL, NULL, kCFStringEncodingUTF8));
        NSString *fullPath = [[_docSet.URL path] stringByAppendingPathComponent:_relativePath];
        return [NSURL URLWithString:[NSString stringWithFormat:@"%@#%@", fullPath, anchor]];
    } else {
        return [_docSet.URL URLByAppendingPathComponent:_relativePath isDirectory:NO];
    }
}

- (NSUInteger)hash
{
    return [_symbolName hash];
}

- (BOOL)isEqual:(id)object
{
    return _language == [(STASymbol *)object language] && _symbolType == [(STASymbol *)object symbolType] && [_symbolName isEqualToString:[(STASymbol *)object symbolName]];
}

- (NSString *)description
{
    switch (_language)
    {
        case STALanguageC:
        {
            switch (_symbolType)
            {
                case STASymbolTypeFunction:
                    return [NSString stringWithFormat:@"%@()", _symbolName];
                case STASymbolTypeMacro:
                    return [NSString stringWithFormat:@"#define %@", _symbolName];
                case STASymbolTypeTypeDefinition:
                    return [NSString stringWithFormat:@"typedef %@", _symbolName];
                case STASymbolTypeEnumerationConstant:
                    return [NSString stringWithFormat:@"enum { %@ }", _symbolName];
                case STASymbolTypeData:
                    return [_symbolName copy];
                default:
                    return [NSString stringWithFormat:@"C: %d (%@)", _symbolType, _symbolName];
            }
        }
        case STALanguageObjectiveC:
        {
            switch (_symbolType)
            {
                case STASymbolTypeClass:
                    return [NSString stringWithFormat:@"@interface %@", _symbolName];
                case STASymbolTypeClassMethod:
                    return [NSString stringWithFormat:@"+%@", _symbolName];
                case STASymbolTypeInstanceMethod:
                    return [NSString stringWithFormat:@"-%@", _symbolName];
                case STASymbolTypeInstanceProperty:
                    return [NSString stringWithFormat:@"@property %@", _symbolName];
                case STASymbolTypeInterfaceClassMethod:
                    return [NSString stringWithFormat:@"+%@", _symbolName];
                case STASymbolTypeInterfaceMethod:
                    return [NSString stringWithFormat:@"-%@", _symbolName];
                case STASymbolTypeInterfaceProperty:
                    return [NSString stringWithFormat:@"@property %@", _symbolName];
                case STASymbolTypeCategory:
                    return [NSString stringWithFormat:@"@interface ?(%@)", _symbolName];
                case STASymbolTypeInterface:
                    return [NSString stringWithFormat:@"@protocol %@", _symbolName];
                default:
                    return [NSString stringWithFormat:@"Obj-C: %d (%@)", _symbolType, _symbolName];
            }
        }
        default:
            return @"";
    }
}

- (BOOL)matches:(NSString *)searchString method:(STASearchMethod)method
{
    switch (method)
    {
        case STASearchMethodPrefix:
            return [[_symbolName lowercaseString] hasPrefix:searchString];
        case STASearchMethodContains:
            return [[_symbolName lowercaseString] rangeOfString:searchString].location != NSNotFound;
    }

    return NO;
}

- (NSComparisonResult)compare:(id)other
{
    NSUInteger o1 = STASymbolTypeOrder(_symbolType);
    NSUInteger o2 = STASymbolTypeOrder([other symbolType]);
    
    if (o1 == o2)
    {
        NSComparisonResult r = [_symbolName compare:[other symbolName]];
        if (r == NSOrderedSame)
        {
            STAPlatform p1 = [_docSet platform];
            STAPlatform p2 = [[other docSet] platform];
            return p1 < p2 ? NSOrderedAscending : p1 > p2 ? NSOrderedDescending : NSOrderedSame;
        }
        return r;
    }
    return o1 < o2 ? NSOrderedAscending : NSOrderedDescending;
}

@end

NSUInteger STASymbolTypeOrder(STASymbolType type)
{
    switch (type)
    {
        case STASymbolTypeClass:                return 0;
        case STASymbolTypeInterface:            return 1;
        case STASymbolTypeCategory:             return 2;
        case STASymbolTypeInstanceProperty:     return 3;
        case STASymbolTypeInterfaceProperty:    return 4;
        case STASymbolTypeInstanceMethod:       return 5;
        case STASymbolTypeInterfaceMethod:      return 6;
        case STASymbolTypeClassMethod:          return 7;
        case STASymbolTypeInterfaceClassMethod: return 8;
        case STASymbolTypeClassConstant:        return 9;
        case STASymbolTypeFunction:             return 10;
        case STASymbolTypeTypeDefinition:       return 11;
        case STASymbolTypeEnumerationConstant:  return 12;
        case STASymbolTypeData:                 return 13;
        case STASymbolTypeMacro:                return 14;
        case STASymbolTypeTag:                  return 15;
        case STASymbolTypeBinding:              return 16;
        case STASymbolTypeUnknown:              return 17;
    }
}

/**
 * Returns the STALanguage associated with the given string.
 *
 * The string may be in the format used by apple_ref anchor tags or the long form used by a doc set index
 * language table.
 *
 * @return The associated STALanguage or STALanguageUnknown is there is no associated language.
 */
STALanguage STALanguageFromNSString(NSString *languageString)
{
    static NSDictionary *languageStrings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        languageStrings = (@{
                           @"c"           : @(STALanguageC),
                           @"occ"         : @(STALanguageObjectiveC),
                           @"objective-c" : @(STALanguageObjectiveC),
                           @"c++"         : @(STALanguageCPlusPlus),
                           @"cpp"         : @(STALanguageCPlusPlus),
                           @"javascript"  : @(STALanguageJavascript),
                           });
    });
    
    NSNumber *language = languageStrings[[languageString lowercaseString]];
    return (language == nil ? STALanguageUnknown :  (STALanguage)[language intValue]);
}

/**
 * Returns the STASymbolType associated with the given string.
 *
 * The string may be in the format used by apple_ref anchor tags or by a doc set index token type table.
 *
 * @return The associated STASymbolType or STASymbolTypeUnknown is there is no associated type.
 */
STASymbolType STASymbolTypeFromNSString(NSString *symbolTypeString)
{
    static NSDictionary *symbolTypeStrings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        symbolTypeStrings = (@{
                             @"func"    : @(STASymbolTypeFunction),
                             @"macro"   : @(STASymbolTypeMacro),
                             @"instm"   : @(STASymbolTypeInstanceMethod),
                             @"econst"  : @(STASymbolTypeEnumerationConstant),
                             @"data"    : @(STASymbolTypeData),
                             @"instp"   : @(STASymbolTypeInstanceProperty),
                             @"intfp"   : @(STASymbolTypeInterfaceProperty),
                             @"intfm"   : @(STASymbolTypeInterfaceMethod),
                             @"intfcm"  : @(STASymbolTypeInterfaceClassMethod),
                             @"tag"     : @(STASymbolTypeTag),
                             @"clm"     : @(STASymbolTypeClassMethod),
                             @"tdef"    : @(STASymbolTypeTypeDefinition),
                             @"cl"      : @(STASymbolTypeClass),
                             @"intf"    : @(STASymbolTypeInterface),
                             @"cat"     : @(STASymbolTypeCategory),
                             @"binding" : @(STASymbolTypeBinding),
                             @"clconst" : @(STASymbolTypeClassConstant)
                             });
    });
    
    NSNumber *symbolType = symbolTypeStrings[[symbolTypeString lowercaseString]];
    return symbolType == nil ? STASymbolTypeUnknown : (STASymbolType)[symbolType intValue];
}
