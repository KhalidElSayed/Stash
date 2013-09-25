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
static NSString * const STAURLKey = @"URL";

@implementation STASymbol

- (id)initWithLanguageString:(NSString *)language symbolTypeString:(NSString *)symbolType symbolName:(NSString *)symbolName url:(NSURL *)url docSet:(STADocSet *)docSet
{
    return [self initWithLanguageString:language symbolTypeString:symbolType symbolName:symbolName parentName:nil url:url docSet:docSet];
}

- (id)initWithLanguageString:(NSString *)language symbolTypeString:(NSString *)symbolType symbolName:(NSString *)symbolName parentName:(NSString *)parentName url:(NSURL *)url docSet:(STADocSet *)docSet
{
    self = [super init];

    NSParameterAssert(url != nil);
    NSParameterAssert(docSet != nil);
    
    if (nil != self)
    {
        [self setLanguage:STALanguageFromNSString(language)];
        [self setSymbolType:STASymbolTypeFromNSString(symbolType)];
        [self setSymbolName:symbolName];
//        [self setParentName:parentName];
        [self setUrl:url];
        [self setDocSet:docSet];
    }
    
    return self;
}

- (instancetype)initWithPropertyListRepresentation:(id)plist docSet:(STADocSet *)docSet {
    if (!(self = [super init]))
        return nil;

    _language = [plist[STALanguageKey] intValue];
    _symbolType = [plist[STATypeKey] intValue];
    _symbolName = plist[STANameKey];
    _url = [NSURL URLWithString:plist[STAURLKey]];
    _docSet = docSet;

    return self;
}

- (id)propertyListRepresentation {
    return @{
        STALanguageKey: @(_language),
        STATypeKey: @(_symbolType),
        STANameKey: _symbolName,
        STAURLKey: [_url absoluteString]
    };
}

- (NSUInteger)hash
{
    return [_symbolName hash];
}

- (BOOL)isEqual:(id)object
{
    return _language == [(STASymbol *)object language] && _symbolType == [(STASymbol *)object symbolType] /*&& [_parentName isEqualToString:[(STASymbol *)object parentName]]*/ && [_symbolName isEqualToString:[(STASymbol *)object symbolName]];
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

STALanguage STALanguageFromNSString(NSString *languageString)
{
    static NSDictionary *languageStrings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        languageStrings = (@{
                           @"c"          : @(STALanguageC),
                           @"occ"        : @(STALanguageObjectiveC),
                           @"cpp"        : @(STALanguageCPlusPlus),
                           @"javascript" : @(STALanguageJavascript)
                           });
    });
    
    NSNumber *language = languageStrings[languageString];
    return (language == nil ? STALanguageUnknown :  (STALanguage)[language intValue]);
}

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
    
    NSNumber *symbolType = symbolTypeStrings[symbolTypeString];
    return symbolType == nil ? STASymbolTypeUnknown : (STASymbolType)[symbolType intValue];
}
