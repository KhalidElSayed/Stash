//
//  STAPreferencesController.m
//  Stash
//
//  Created by Thomas Davie on 04/06/2012.
//  Copyright (c) 2012 Hunted Cow Studios. All rights reserved.
//

#import "STAPreferencesController.h"

static NSString * const STAShowDockIconKey = @"ShowDockIcon";
static NSString * const STAShowMenuBarIconKey = @"ShowMenuBarIcon";
static NSString * const STAModifierFlagsKey = @"ModifierFlags";
static NSString * const STAKeyboardShortcutKey = @"KeyboardShortcut";
static NSString * const STADisabledDocSetsKey = @"DisabledDocSets";

static NSString *descriptionStringFromChar(unichar c)
{
    switch (c)
    {
        case ' ':
            return @"Space";
        case NSBackspaceCharacter:
        {
            unichar d = 0x232b;
            return [NSString stringWithCharacters:&d length:1];
        }
        case NSDeleteCharacter:
        {
            unichar d = 0x2326;
            return [NSString stringWithCharacters:&d length:1];
        }
        case '\n':
        {
            unichar d = 0x23ce;
            return [NSString stringWithCharacters:&d length:1];
        }
        case 0x1b:
        {
            unichar d = 0x238b;
            return [NSString stringWithCharacters:&d length:1];
        }
        case 0x9:
        {
            unichar d = 0x21e5;
            return [NSString stringWithCharacters:&d length:1];
        }
        default:
            return [[NSString stringWithCharacters:&c length:1] uppercaseString];
    }
}

@interface STAPreferencesController ()

@property (weak) id eventMonitor;

@end

@implementation STAPreferencesController {
    NSUserDefaults *_defaults;
    NSArray *_registeredDocSets;
    NSMutableSet *_disabledDocSetIdentifiers;
    IBOutlet __weak NSButton *_showDockIconButton;
    IBOutlet __weak NSButton *_showMenuBarIconButton;
}

- (id)initWithNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle
{
    self = [super init];
    
    if (nil != self)
    {
        NSArray *topLevelObjects = nil;
        BOOL success = [[[NSNib alloc] initWithNibNamed:nibName bundle:bundle] instantiateWithOwner:self topLevelObjects:&topLevelObjects];
        if (!success)
        {
            return nil;
        }
        _defaults = [NSUserDefaults standardUserDefaults];
        [_defaults registerDefaults:@{
            STAShowDockIconKey: @YES,
            STAModifierFlagsKey: @(NSCommandKeyMask | NSControlKeyMask),
            STAKeyboardShortcutKey: @(' '),
            STADisabledDocSetsKey: @[]
        }];

        _registeredDocSets = @[];
        _disabledDocSetIdentifiers = [NSMutableSet setWithArray:[_defaults arrayForKey:STADisabledDocSetsKey]];
    }
    
    return self;
}

- (void)showWindow
{
    [self setupShortcutText];

    [_showDockIconButton setState:[_defaults boolForKey:STAShowDockIconKey] ? NSOnState : NSOffState];
    [_showMenuBarIconButton setState:[_defaults boolForKey:STAShowMenuBarIconKey] ? NSOnState : NSOffState];

    [[self window] center];
    [[self window] makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)setupShortcutText
{
    NSMutableString *keyboardShortcutString = [NSMutableString stringWithString:@""];
    NSUInteger modifierFlags = [self keyboardShortcutModifierFlags];
    unichar command = 0x2318;
    unichar alt     = 0x2325;
    unichar ctrl    = 0x2303;
    unichar shift   = 0x21E7;
    if (modifierFlags & NSControlKeyMask)
    {
        [keyboardShortcutString appendString:[NSString stringWithCharacters:&ctrl length:1]];
    }
    if (modifierFlags & NSAlternateKeyMask)
    {
        [keyboardShortcutString appendString:[NSString stringWithCharacters:&alt length:1]];
    }
    if (modifierFlags & NSShiftKeyMask)
    {
        [keyboardShortcutString appendString:[NSString stringWithCharacters:&shift length:1]];
    }
    if (modifierFlags & NSCommandKeyMask)
    {
        [keyboardShortcutString appendString:[NSString stringWithCharacters:&command length:1]];
    }
    [keyboardShortcutString appendString:descriptionStringFromChar([self keyboardShortcutCharacter])];
    [[self shortcutText] setStringValue:keyboardShortcutString];
}

- (void)registerDocSets:(NSArray *)docSets
{
    _registeredDocSets = [docSets sortedArrayUsingComparator:^NSComparisonResult(STADocSet *obj1, STADocSet *obj2) {
        return [obj1.name localizedStandardCompare:obj2.name];
    }];

    [[self docsetTable] reloadData];
}

- (IBAction)changeShortcut:(id)sender
{
    [NSEvent removeMonitor:[self eventMonitor]];
    [self setEventMonitor:[NSEvent addLocalMonitorForEventsMatchingMask:NSKeyUpMask handler:^ NSEvent * (NSEvent *e)
                           {
                               [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:[e modifierFlags] & NSDeviceIndependentModifierFlagsMask]
                                                                         forKey:STAModifierFlagsKey];
                               [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[[e charactersIgnoringModifiers] characterAtIndex:0]]
                                                                         forKey:STAKeyboardShortcutKey];
                               [self setupShortcutText];
                               [[self shortcutButton] setState:NSOffState];
                               [self performSelector:@selector(removeEventMonitor) withObject:nil afterDelay:0.0];
                               [[self delegate] preferencesControllerDidUpdateMenuShortcut:self];
                               return e;
                           }]];
}

- (IBAction)showDockIconChanged:(id)sender {
    [_defaults setBool:([_showDockIconButton state] == NSOnState) forKey:STAShowDockIconKey];
}

- (IBAction)showMenuBarIconChanged:(id)sender {
    [_defaults setBool:([_showMenuBarIconButton state] == NSOnState) forKey:STAShowMenuBarIconKey];
}

- (void)removeEventMonitor
{
    [NSEvent removeMonitor:[self eventMonitor]];
    [self setEventMonitor:nil];
}

- (BOOL)isMonitoringForEvents
{
    return [self eventMonitor] != nil;
}

- (BOOL)appShouldHideWhenNotActive {
    return !self.shouldShowDockIcon;
}

- (BOOL)shouldShowDockIcon {
    return [_defaults boolForKey:STAShowDockIconKey];
}

- (BOOL)shouldShowMenuBarIcon {
    return [_defaults boolForKey:STAShowMenuBarIconKey];
}

- (NSArray *)enabledDocsets
{
    return [_registeredDocSets objectsAtIndexes:[_registeredDocSets indexesOfObjectsPassingTest:^BOOL(STADocSet *docSet, NSUInteger idx, BOOL *stop) {
        return ([_disabledDocSetIdentifiers containsObject:docSet.identifier] == NO);
    }]];
}

- (unichar)keyboardShortcutCharacter
{
    return (unichar) [[[NSUserDefaults standardUserDefaults] objectForKey:STAKeyboardShortcutKey] intValue];
}

- (NSUInteger)keyboardShortcutModifierFlags
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:STAModifierFlagsKey] unsignedIntegerValue];
}

#pragma mark - Table View Data Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_registeredDocSets count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0)
    {
        return nil;
    }

    STADocSet *docSet = [_registeredDocSets objectAtIndex:(NSUInteger)row];

    if ([[tableColumn identifier] isEqualToString:@"name"])
    {
        return docSet.name;
    }
    else
    {
        return @([_disabledDocSetIdentifiers containsObject:docSet.identifier] == NO);
    }
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (row < 0)
    {
        return;
    }

    STADocSet *docSet = [_registeredDocSets objectAtIndex:(NSUInteger)row];

    if (![[tableColumn identifier] isEqualToString:@"name"])
    {
        if (![object boolValue])
        {
            [_disabledDocSetIdentifiers addObject:docSet.identifier];
        }
        else
        {
            [_disabledDocSetIdentifiers removeObject:docSet.identifier];
        }
        [[NSUserDefaults standardUserDefaults] setObject:[_disabledDocSetIdentifiers allObjects] forKey:STADisabledDocSetsKey];
        [[self delegate] preferencesControllerDidUpdateSelectedDocsets:self];
    }
}

@end
