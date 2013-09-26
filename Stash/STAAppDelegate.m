//
//  STAAppDelegate.m
//  Stash
//
//  Created by Thomas Davie on 01/06/2012.
//  Copyright (c) 2012 Thomas Davie. All rights reserved.
//

#import "STAAppDelegate.h"

@implementation STAAppDelegate {
    STADocSetStore *_docSetStore;
    NSURL *_cacheURL;
}

- (id)init
{
    self = [super init];

    if (nil != self)
    {
        [self setPreferencesController:[[STAPreferencesController alloc] initWithNibNamed:@"STAPreferencesController" bundle:nil]];
        [[self preferencesController] setDelegate:self];

        if (self.preferencesController.shouldShowDockIcon)
        {
            [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
    }

    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[self mainWindowController] setPreferencesController:[self preferencesController]];
    [[self mainWindowController] windowDidLoad];

    [self userDefaultsDidChange:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userDefaultsDidChange:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];

    if (![[self preferencesController] appShouldHideWhenNotActive])
    {
        [self toggleStashWindow:nil];
    }
    
    unichar c = [[self preferencesController] keyboardShortcutCharacter];
    [[self openStashMenuItem] setKeyEquivalent:[NSString stringWithCharacters:&c length:1]];
    [[self openStashMenuItem] setKeyEquivalentModifierMask:[[self preferencesController] keyboardShortcutModifierFlags]];
    
    void(^handler)(NSEvent *) = ^(NSEvent *e)
    {
        if (![[self preferencesController] isMonitoringForEvents])
        {
            NSUInteger modifiers = [e modifierFlags] & NSDeviceIndependentModifierFlagsMask;
            NSUInteger desiredModifiers = [[self preferencesController] keyboardShortcutModifierFlags];
            if (modifiers == desiredModifiers && [[e charactersIgnoringModifiers] characterAtIndex:0] == [[self preferencesController] keyboardShortcutCharacter])
            {
                [self toggleStashWindow:self];
            }
        }
    };
    
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSKeyUpMask handler:handler];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyUpMask handler:^ NSEvent * (NSEvent *e) { handler(e); return e; }];

    [self migrateAppDirectories];

    _docSetStore = [[STADocSetStore alloc] initWithCacheDirectory:_cacheURL delegate:self.mainWindowController delegateQueue:dispatch_get_main_queue()];
    self.mainWindowController.docsetStore = _docSetStore;
    [_docSetStore loadWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.preferencesController registerDocSets:_docSetStore.docSets];
            [self.mainWindowController setEnabled:YES];
        });
    }];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)hasVisibleWindows
{
    if (!hasVisibleWindows)
    {
        [self toggleStashWindow:nil];
    }

    return YES;
}

- (void)migrateAppDirectories {
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Remove any existing index under App Support
    NSURL *appSupportURL = [fileManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
    appSupportURL = [appSupportURL URLByAppendingPathComponent:@"Stash" isDirectory:YES];
    if ([appSupportURL checkResourceIsReachableAndReturnError:nil]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [fileManager removeItemAtURL:appSupportURL error:nil];
        });
    }

    NSURL *cachesURL = [fileManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    if (error) {
        NSLog(@"Error creating caches directory: %@", error);
        return;
    }

    _cacheURL = [cachesURL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier] isDirectory:YES];
    [fileManager createDirectoryAtURL:_cacheURL withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        NSLog(@"Error creating cache directory: %@", error);
    }
}

- (void)userDefaultsDidChange:(NSNotification *)notification {
    if (self.preferencesController.shouldShowDockIcon) {
        if ([NSApp activationPolicy] != NSApplicationActivationPolicyRegular) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
    }

    if (self.preferencesController.shouldShowMenuBarIcon) {
        if (!_statusItem) {
            _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
            [_statusItem setMenu:[self statusMenu]];
            [_statusItem setTitle:@"Stash"];
            [_statusItem setHighlightMode:YES];
        }
    } else {
        if (_statusItem) {
            [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
            _statusItem = nil;
        }
    }
}

- (IBAction)toggleStashWindow:(id)sender
{
    if ([[self window] isVisible])
    {
        [[self window] close];
        [[NSApplication sharedApplication] hide:self];
    }
    else
    {
        [[self window] makeKeyAndOrderFront:self];
        [[self window] setNextResponder:self];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)cancelOperation:(id)sender
{
    if ([[self preferencesController] appShouldHideWhenNotActive])
    {
        [self toggleStashWindow:sender];
    }
}

- (void)applicationDidResignActive:(NSNotification *)notification
{
    if ([[self preferencesController] appShouldHideWhenNotActive])
    {
        [[self window] close];
    }
}

- (IBAction)openPreferences:(id)sender
{
    [[self preferencesController] showWindow];
}

#pragma mark - Prefs Delegate
- (void)preferencesControllerDidUpdateSelectedDocsets:(STAPreferencesController *)prefsController
{
    for (STADocSet *docset in [_docSetStore docSets])
    {
        if (![[prefsController enabledDocsets] containsObject:docset])
        {
            [docset unload];
        }
    }
}

- (void)preferencesControllerDidUpdateMenuShortcut:(STAPreferencesController *)prefsController
{
    unichar c = [[self preferencesController] keyboardShortcutCharacter];
    [[self openStashMenuItem] setKeyEquivalent:[NSString stringWithCharacters:&c length:1]];
    [[self openStashMenuItem] setKeyEquivalentModifierMask:[[self preferencesController] keyboardShortcutModifierFlags]];
}

@end
