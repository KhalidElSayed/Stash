#import "STADatabaseDocSetIndexer.h"
#import <sqlite3.h>

/**
 * Indexes a doc set by querying its index database.
 *
 * This method of indexing is evil in that it directly reads from a Core Data database that it does not
 * control. However, it offers significant advantages over other indexing methods:
 *
 * - For some third-party doc sets the database is the only place that the API information is stored in
 *   an easily extractable format.
 *
 * - Extracting API information from the database is on the order of 10 times faster than parsing HTML
 *   documents. Complete API information for a platform SDK can be extracted in under a second.
 */
@implementation STADatabaseDocSetIndexer

- (NSArray *)indexDocSet:(STADocSet *)docSet progressReporter:(STAProgressReporter *)progressReporter {
    NSBundle *bundle = [NSBundle bundleWithURL:docSet.URL];
    NSString *dbPath = [bundle pathForResource:@"docSet" ofType:@"dsidx"];
    if (!dbPath) {
        return nil;
    }

    NSString *baseDocumentsPath = [bundle pathForResource:@"Documents" ofType:@""];
    baseDocumentsPath = [baseDocumentsPath substringFromIndex:[[docSet.URL path] length] + 1];
    if ([baseDocumentsPath length] < 1) {
        return nil;
    }

    sqlite3 *db = NULL;
    int rc = sqlite3_open([dbPath fileSystemRepresentation], &db);
    if (rc != SQLITE_OK) {
        return nil;
    }

    NSDictionary *languageMap = [self languageMapForDatabase:db];
    NSDictionary *tokenTypeMap = [self tokenTypeMapForDatabase:db];
    if (!languageMap || !tokenTypeMap) {
        sqlite3_close(db);
        return nil;
    }

    const char *sql = "SELECT "
    "ZTOKEN.ZLANGUAGE as language, "
    "ZTOKEN.ZTOKENTYPE as type, "
    "ZTOKEN.ZTOKENNAME as name, "
    "ZFILEPATH.ZPATH as path, "
    "ZTOKENMETAINFORMATION.ZANCHOR as anchor "
    "FROM ZTOKEN "
    "LEFT OUTER JOIN ZTOKENMETAINFORMATION ON ZTOKEN.ZMETAINFORMATION = ZTOKENMETAINFORMATION.Z_PK "
    "LEFT OUTER JOIN ZFILEPATH ON ZTOKENMETAINFORMATION.ZFILE = ZFILEPATH.Z_PK "
    "WHERE path IS NOT NULL;";

    sqlite3_stmt *stmt = NULL;
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_close(db);
        return nil;
    }

    NSMutableArray *symbols = [NSMutableArray array];

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        @autoreleasepool {
            NSNumber *key = @(sqlite3_column_int(stmt, 0));
            NSNumber *language = languageMap[key];
            if (!language)
                continue;

            key = @(sqlite3_column_int(stmt, 1));
            NSNumber *tokenType = tokenTypeMap[key];
            if (!tokenType)
                continue;

            NSString *name;
            NSString *documentPath;
            NSString *anchorName;
            const char *string;

            string = (const char *)sqlite3_column_text(stmt, 2);
            if (string) {
                name = @(string);
            }

            string = (const char *)sqlite3_column_text(stmt, 3);
            if (string) {
                documentPath = @(string);
            }

            string = (const char *)sqlite3_column_text(stmt, 4);
            if (string) {
                anchorName = @(string);
            }

            NSString *relativePath = [baseDocumentsPath stringByAppendingPathComponent:documentPath];

            STASymbol *symbol = [[STASymbol alloc] initWithLanguage:[language intValue]
                                                         symbolType:[tokenType intValue]
                                                         symbolName:name
                                               relativePathToDocSet:relativePath
                                                             anchor:anchorName
                                                             docSet:docSet];

            [symbols addObject:symbol];
        }
    }

    sqlite3_finalize(stmt);
    sqlite3_close(db);

    return symbols;
}

- (NSDictionary *)languageMapForDatabase:(sqlite3 *)db {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT Z_PK, ZFULLNAME FROM ZAPILANGUAGE;";

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return nil;
    }

    NSMutableDictionary *languageMap = [NSMutableDictionary dictionary];

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        const char *languageString = (const char *)sqlite3_column_text(stmt, 1);
        if (!languageString)
            continue;

        STALanguage language = STALanguageFromNSString(@(languageString));
        if (language != STALanguageUnknown) {
            NSNumber *key = @(sqlite3_column_int(stmt, 0));
            languageMap[key] = @(language);
        }
    }

    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        return nil;
    }

    return languageMap;
}

- (NSDictionary *)tokenTypeMapForDatabase:(sqlite3 *)db {
    sqlite3_stmt *stmt = NULL;
    const char *sql = "SELECT Z_PK, ZTYPENAME FROM ZTOKENTYPE;";

    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return nil;
    }

    NSMutableDictionary *tokenTypeMap = [NSMutableDictionary dictionary];

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        const char *typeString = (const char *)sqlite3_column_text(stmt, 1);
        if (!typeString)
            continue;

        STASymbolType type = STASymbolTypeFromNSString(@(typeString));
        if (type != STASymbolTypeUnknown) {
            NSNumber *key = @(sqlite3_column_int(stmt, 0));
            tokenTypeMap[key] = @(type);
        }
    }

    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        return nil;
    }

    return tokenTypeMap;
}

@end
