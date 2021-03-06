//
//  STASymbol.h
//  Stash
//
//  Created by Thomas Davie on 02/06/2012.
//  Copyright (c) 2012 Hunted Cow Studios. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum : unsigned char
{
    STALanguageUnknown    = 0,
    STALanguageC          = 1,
    STALanguageCPlusPlus  = 2,
    STALanguageObjectiveC = 3,
    STALanguageJavascript = 4
} STALanguage;

typedef enum : unsigned char
{
    STASymbolTypeUnknown              = 0,
    STASymbolTypeFunction             = 1,
    STASymbolTypeMacro                = 2,
    STASymbolTypeTypeDefinition       = 3,
    STASymbolTypeClass                = 4,
    STASymbolTypeInterface            = 5,
    STASymbolTypeCategory             = 6,
    STASymbolTypeClassMethod          = 7,
    STASymbolTypeClassConstant        = 8,
    STASymbolTypeInstanceMethod       = 9,
    STASymbolTypeInstanceProperty     = 10,
    STASymbolTypeInterfaceMethod      = 11,
    STASymbolTypeInterfaceClassMethod = 12,
    STASymbolTypeInterfaceProperty    = 13,
    STASymbolTypeEnumerationConstant  = 14,
    STASymbolTypeData                 = 15,
    STASymbolTypeTag                  = 16,
    STASymbolTypeBinding              = 17
} STASymbolType;

typedef enum
{
    STASearchMethodPrefix,
    STASearchMethodContains
} STASearchMethod;

STALanguage STALanguageFromNSString(NSString *languageString);
STASymbolType STASymbolTypeFromNSString(NSString *symbolTypeString);

@class STADocSet;

@interface STASymbol : NSObject

@property (nonatomic, readonly) STALanguage language;
@property (nonatomic, readonly) STASymbolType symbolType;
@property (nonatomic, readonly) NSString *symbolName;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly, unsafe_unretained) STADocSet *docSet;

- (instancetype)initWithLanguage:(STALanguage)language
                      symbolType:(STASymbolType)symbolType
                      symbolName:(NSString *)symbolName
            relativePathToDocSet:(NSString *)relativePath
                          anchor:(NSString *)anchor
                          docSet:(STADocSet *)docSet;

- (instancetype)initWithLanguage:(STALanguage)language
                      symbolType:(STASymbolType)symbolType
                      symbolName:(NSString *)symbolName
                             URL:(NSURL *)fileURL
                          anchor:(NSString *)anchor
                          docSet:(STADocSet *)docSet;

- (instancetype)initWithLanguageString:(NSString *)language
                symbolTypeString:(NSString *)symbolType
                      symbolName:(NSString *)symbolName
                             URL:(NSURL *)fileURL
                          anchor:(NSString *)anchor
                          docSet:(STADocSet *)docSet;

- (instancetype)initWithPropertyListRepresentation:(id)plist docSet:(STADocSet *)docSet;
- (id)propertyListRepresentation;

- (BOOL)matches:(NSString *)searchString method:(STASearchMethod)method;

- (NSComparisonResult)compare:(id)other;

@end
