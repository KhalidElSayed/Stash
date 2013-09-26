//
//  STAMainWindowController.m
//  Stash
//
//  Created by Tom Davie on 03/03/2013.
//
//

#import "STAMainWindowController.h"

#import "STASymbolTableViewCell.h"

NSImage *NSImageFromSTASymbolType(STASymbolType t);
NSImage *NSImageFromSTAPlatform(STAPlatform p);

@interface STAMainWindowController () <NSTableViewDelegate, NSTableViewDataSource>

@property (copy) NSString *currentSearchString;
@property (strong) NSArray *sortedResults;
@property (assign, getter=isFindUIShowing) BOOL findUIShowing;
@property (weak) NSSearchField *selectedSearchField;

- (void)showFindUI;
- (void)searchAgain:(BOOL)backwards;

@end

@implementation STAMainWindowController {
    NSArray *_indexingDocSets;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    NSRect findBarRect = [[self findBar] frame];
    findBarRect.origin.y += findBarRect.size.height;
    findBarRect.size.height = 0.0f;
    [[self findBar] setFrame:findBarRect];
    NSRect resultWebViewFrame = [[self resultWebView] frame];
    resultWebViewFrame.size.height = findBarRect.origin.y - resultWebViewFrame.origin.y;
    [[self resultWebView] setFrame:resultWebViewFrame];
    
    [[[self resultWebView] preferences] setJavaEnabled:NO];
    [[[self resultWebView] preferences] setJavaScriptEnabled:YES];
    [[[self resultWebView] preferences] setJavaScriptCanOpenWindowsAutomatically:NO];
    [[[self resultWebView] preferences] setPlugInsEnabled:NO];

    // Apple's docsets look for "Xcode/version" in the user-agent and hide
    // certain elements such as the ADC header.
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *userAgent = [NSString stringWithFormat:@"%@/%@ (like Xcode/4)",
                           bundleInfo[@"CFBundleName"],
                           bundleInfo[@"CFBundleShortVersionString"]];
    [[self resultWebView] setApplicationNameForUserAgent:userAgent];

    _indexingDocSets = @[];

    [self updateWindow];
    
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^ NSEvent * (NSEvent *e)
     {
         NSUInteger modifiers = [e modifierFlags] & NSDeviceIndependentModifierFlagsMask;
         if (modifiers == NSCommandKeyMask &&
             ([[e charactersIgnoringModifiers] isEqualToString:@"f"] ||
              ([[e charactersIgnoringModifiers] isEqualToString:@"g"] && [self isFindUIShowing])))
         {
             return nil;
         }
         if (modifiers == (NSCommandKeyMask | NSShiftKeyMask) &&
             [[e charactersIgnoringModifiers] isEqualToString:@"G"] &&
             [self isFindUIShowing])
         {
             return nil;
         }
         return e;
     }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyUpMask handler:^ NSEvent * (NSEvent *e)
     {
         NSUInteger modifiers = [e modifierFlags] & NSDeviceIndependentModifierFlagsMask;
         if (modifiers == NSCommandKeyMask && [[e charactersIgnoringModifiers] isEqualToString:@"f"])
         {
             if (![self isFindUIShowing])
             {
                 [self showFindUI];
             }
             else
             {
                 [self hideSearchBar:self];
             }
             return nil;
         }
         if (modifiers == NSCommandKeyMask || modifiers == (NSCommandKeyMask | NSShiftKeyMask))
         {
             if (([[e charactersIgnoringModifiers] isEqualToString:@"g"] || [[e charactersIgnoringModifiers] isEqualToString:@"G"]) && [self isFindUIShowing])
             {
                 [self searchAgain:(modifiers & NSShiftKeyMask) == 0 ? YES : NO];
                 return nil;
             }
             
         }
         return e;
     }];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [self updateWindow];
}

- (void)updateWindow {
    if (self.docsetStore.loaded) {
        if ([self.docsetStore.docSets count] > 0) {
            [self.docsetsNotFoundView setHidden:YES];

            if (self.docsetStore.indexing) {
                [self.titleView setStringValue:@"Stash is Indexing, Please Wait..."];
                [self.indexingDocsetsContainer setHidden:NO];
                [self.searchField setEnabled:NO];
            } else {
                [self.titleView setStringValue:self.resultWebView.mainFrameTitle];
                [self.indexingDocsetsContainer setHidden:YES];
                [self.searchField setEnabled:YES];
                [self.searchField selectText:self];
            }
        } else {
            [self.searchField setEnabled:NO];
            [self.docsetsNotFoundView setHidden:NO];
            [self.indexingDocsetsContainer setHidden:YES];
        }
    } else {
        [self.titleView setStringValue:@"Stash is Loading, Please Wait..."];
        [self.searchField setEnabled:NO];
        [self.docsetsNotFoundView setHidden:YES];
        [self.indexingDocsetsContainer setHidden:YES];
    }
}

- (void)showFindUI
{
    [[self window] makeFirstResponder:[self inPageSearchField]];
    if (![self isFindUIShowing])
    {
        [self setFindUIShowing:YES];
        CGRect findBarFrame = [[self findBar] frame];
        findBarFrame.origin.y -= 25.0f;
        findBarFrame.size.height = 25.0f;
        NSRect resultWebViewFrame = [[self resultWebView] frame];
        resultWebViewFrame.size.height = findBarFrame.origin.y - resultWebViewFrame.origin.y;
        [NSAnimationContext runAnimationGroup:^ (NSAnimationContext *ctx)
         {
             [ctx setDuration:0.15];
             [[[self findBar] animator] setFrame:findBarFrame];
             [[[self resultWebView] animator] setFrame:resultWebViewFrame];
         }
                            completionHandler:^(){}];
    }
}

- (IBAction)hideSearchBar:(id)sender
{
    if ([self isFindUIShowing])
    {
        if ([self selectedSearchField] != [self searchField])
        {
            [[self window] makeFirstResponder:[self searchField]];
        }
        [self setFindUIShowing:NO];
        CGRect findBarFrame = [[self findBar] frame];
        findBarFrame.origin.y += findBarFrame.size.height;
        findBarFrame.size.height = 0.0f;
        NSRect resultWebViewFrame = [[self resultWebView] frame];
        resultWebViewFrame.size.height = findBarFrame.origin.y - resultWebViewFrame.origin.y;
        [NSAnimationContext runAnimationGroup:^ (NSAnimationContext *ctx)
         {
             [ctx setDuration:0.15];
             [[[self findBar] animator] setFrame:findBarFrame];
             [[[self resultWebView] animator] setFrame:resultWebViewFrame];
         }
                            completionHandler:^(){}];
    }
}

- (IBAction)searchWithinPage:(id)sender
{
    [[self resultWebView] searchFor:[[self inPageSearchField] stringValue]
                          direction:YES
                      caseSensitive:NO
                               wrap:YES];
}

- (void)searchAgain:(BOOL)backwards
{
    [[self resultWebView] searchFor:[[self inPageSearchField] stringValue]
                          direction:backwards
                      caseSensitive:NO
                               wrap:YES];
}

- (IBAction)search:(id)sender
{
    NSString *searchString = [[[self searchField] stringValue] lowercaseString];
    [self hideSearchBar:self];
    [self setCurrentSearchString:searchString];

    STASearchMethod method = [self.searchMethodSelector selectedRow] == 0 ? STASearchMethodPrefix : STASearchMethodContains;
    [self.docsetStore searchString:searchString inDocSets:self.preferencesController.enabledDocsets method:method completionHandler:^(NSArray *results) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([searchString isEqualToString:[self currentSearchString]]) {
                [self setSortedResults:results];
                [[self resultsTable] reloadData];
                if ([self.sortedResults count] > 0) {
                    [self.resultsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                }
            }
        });
    }];
}

- (IBAction)setSearchMethod:(id)sender
{
    [self search:sender];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    [[self window] makeFirstResponder:[self searchField]];
    [[self searchField] selectText:self];
}

- (void)docSetStoreDidUpdateDocSets:(STADocSetStore *)docSetStore {
    [self.preferencesController registerDocSets:docSetStore.docSets];
    _indexingDocSets = [docSetStore.docSets sortedArrayUsingComparator:^NSComparisonResult(STADocSet *obj1, STADocSet *obj2) {
        return [obj1.name localizedStandardCompare:obj2.name];
    }];
    [[self indexingDocsetsView] reloadData];
    [self search:self.searchField];
}

- (void)docSetStoreWillBeginIndexing:(STADocSetStore *)docSetStore {
    [self updateWindow];
}

- (void)docSetStore:(STADocSetStore *)docSetStore didReachIndexingProgress:(double)progress forDocSet:(STADocSet *)docSet {
    NSUInteger index = [_indexingDocSets indexOfObject:docSet];
    if (index != NSNotFound) {
        [self.indexingDocsetsView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index] columnIndexes:[NSIndexSet indexSetWithIndex:1]];
    }
}

- (void)docSetStoreDidFinishIndexing:(STADocSetStore *)docSetStore {
    [self updateWindow];
    [self search:self.searchField];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return tableView == [self indexingDocsetsView] ? [_indexingDocSets count] : [[self sortedResults] count];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSInteger row = [[self resultsTable] selectedRow];
    if (row < [[self sortedResults] count] && row != -1)
    {
        STASymbol *symbol = [[self sortedResults] objectAtIndex:(NSUInteger) row];
        NSURLRequest *request = [NSURLRequest requestWithURL:[symbol url]];
        [[[self resultWebView] mainFrame] loadRequest:request];
    }
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)aRow
{
    if (aRow < 0) {
        return nil;
    }

    NSUInteger row = (NSUInteger) aRow;

    if (tableView == [self resultsTable])
    {
        STASymbolTableViewCell *view = [tableView makeViewWithIdentifier:@"ResultView" owner:self];
        if (!view) {
            view = [[STASymbolTableViewCell alloc] initWithFrame:NSZeroRect];
            [view setIdentifier:@"ResultView"];
        }

        [view setSymbolName:row < [[self sortedResults] count] ? [[[self sortedResults] objectAtIndex:row] symbolName] : @""];
        [view setSymbolTypeImage:NSImageFromSTASymbolType([[[self sortedResults] objectAtIndex:row] symbolType])];
        [view setPlatformImage:NSImageFromSTAPlatform([[[[self sortedResults] objectAtIndex:row] docSet] platform])];
        return view;
    }
    else
    {
        STADocSet *docSet = [_indexingDocSets objectAtIndex:row];

        if ([[tableColumn identifier] isEqualToString:@"docset"])
        {
            NSTextField *textField = [tableView makeViewWithIdentifier:@"IndexingNameView" owner:self];
            if (!textField) {
                textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
                [textField setIdentifier:@"IndexingNameView"];
                [textField setEditable:NO];
                [textField setSelectable:NO];
                [textField setBordered:NO];
                [textField setDrawsBackground:NO];
                [textField setBezeled:NO];
                [[textField cell] setLineBreakMode:NSLineBreakByTruncatingTail];
            }

            [textField setStringValue:docSet.name];
            return textField;
        }
        else if ([[tableColumn identifier] isEqualToString:@"progress"])
        {
            if (docSet.indexingProgress < 100.0) {
                NSProgressIndicator *progressView = [tableView makeViewWithIdentifier:@"IndexingProgressView" owner:self];
                if (!progressView) {
                    progressView = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 16.0f, 16.0f)];
                    [progressView setIdentifier:@"IndexingProgressView"];
                    [progressView setStyle:NSProgressIndicatorSpinningStyle];
                    [progressView setControlSize:NSSmallControlSize];
                    [progressView setIndeterminate:NO];
                }

                [progressView setDoubleValue:docSet.indexingProgress];
                return progressView;
            } else {
                NSImageView *tick = [tableView makeViewWithIdentifier:@"TickImageView" owner:self];
                if (!tick) {
                    tick = [[NSImageView alloc] initWithFrame:NSZeroRect];
                    [tick setIdentifier:@"TickImageView"];
                    [tick setImageAlignment:NSImageAlignLeft];
                    [tick setImage:[NSImage imageNamed:@"Tick"]];
                }

                return tick;
            }
        }
    }

    return nil;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return tableView == [self resultsTable];
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    [[self titleView] setStringValue:title];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    [sender stringByEvaluatingJavaScriptFromString:@"(function(){ var button = document.getElementById('xcode_leave_feedback'); if(button){ button.setAttribute('class', 'hidden'); }})();"];
}

- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor
{
    if ([control isKindOfClass:[NSSearchField class]])
    {
        [self setSelectedSearchField:(NSSearchField *)control];
    }
    return YES;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
    {
        return 229.0f;
    }
    return proposedMinimumPosition;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view
{
    return view != [self searchColumn];
}

@end

NSImage *NSImageFromSTAPlatform(STAPlatform p)
{
    switch (p)
    {
        case STAPlatformIOS:
            return [NSImage imageNamed:@"iOS"];
        case STAPlatformMacOS:
            return [NSImage imageNamed:@"MacOS"];
        default:
            return nil;
    }
}

NSImage *NSImageFromSTASymbolType(STASymbolType t)
{
    switch (t)
    {
        case STASymbolTypeFunction:
            return [NSImage imageNamed:@"Function"];
        case STASymbolTypeMacro:
            return [NSImage imageNamed:@"Macro"];
        case STASymbolTypeTypeDefinition:
            return [NSImage imageNamed:@"Typedef"];
        case STASymbolTypeClass:
            return [NSImage imageNamed:@"Class"];
        case STASymbolTypeInterface:
            return [NSImage imageNamed:@"Protocol"];
        case STASymbolTypeCategory:
            return [NSImage imageNamed:@"Category"];
        case STASymbolTypeClassMethod:
            return [NSImage imageNamed:@"Method"];
        case STASymbolTypeClassConstant:
            return nil;
        case STASymbolTypeInstanceMethod:
            return [NSImage imageNamed:@"Method"];
        case STASymbolTypeInstanceProperty:
            return [NSImage imageNamed:@"Property"];
        case STASymbolTypeInterfaceMethod:
            return [NSImage imageNamed:@"Method"];
        case STASymbolTypeInterfaceClassMethod:
            return [NSImage imageNamed:@"Method"];
        case STASymbolTypeInterfaceProperty:
            return [NSImage imageNamed:@"Property"];
        case STASymbolTypeEnumerationConstant:
            return [NSImage imageNamed:@"Enum"];
        case STASymbolTypeData:
            return [NSImage imageNamed:@"Value"];
        default:
            return nil;
    }
}
