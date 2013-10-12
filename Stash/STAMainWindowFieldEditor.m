#import "STAMainWindowFieldEditor.h"

@implementation STAMainWindowFieldEditor

/**
 * Hides the text view's find action support.
 *
 * This allows the search for a handler of find actions to continue further up the responder chain,
 * supporting custom find implementations in the parent view or window.
 */
- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(performFindPanelAction:) || aSelector == @selector(performTextFinderAction:))
        return NO;

    return [super respondsToSelector:aSelector];
}

@end
