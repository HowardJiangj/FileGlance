#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(id element, CFStringRef key) {
    CFTypeRef result = NULL;
    AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element, key, &result);
    return CFBridgingRelease(result);
}

static NSURL *itemURL(id node) {
    id value = attribute(node, kAXURLAttribute);
    if ([value isKindOfClass:NSString.class]) value = [NSURL URLWithString:value];
    if (![value isKindOfClass:NSURL.class] || ![value isFileURL]) return nil;
    NSURL *url = value;
    return url.isFileReferenceURL ? url.filePathURL : url;
}

// Finder's list view may put the URL on the name cell's child, even if
// the pointer hits the size or modification-date cell in the same row.
static NSURL *urlInRow(id node, NSUInteger depth, NSUInteger *budget) {
    if (!*budget) return nil;
    --*budget;
    NSURL *url = itemURL(node);
    if (url || !depth) return url;
    for (id child in attribute(node, kAXChildrenAttribute)) {
        NSString *role = attribute(child, kAXRoleAttribute);
        if ([role isEqual:@"AXRow"] || [role isEqual:@"AXList"] || [role isEqual:@"AXOutline"]) continue;
        url = urlInRow(child, depth - 1, budget);
        if (url || !*budget) break;
    }
    return url;
}

NSURL *FinderFileAtPoint(CGPoint point, pid_t finderPID) {
    if (finderPID <= 0) return nil;
    AXUIElementRef system = AXUIElementCreateSystemWide();
    AXUIElementSetMessagingTimeout(system, 0.35);
    AXUIElementRef hit = NULL;
    AXUIElementCopyElementAtPosition(system, point.x, point.y, &hit);
    CFRelease(system);
    if (!hit) return nil;
    pid_t owner = 0;
    AXUIElementGetPid(hit, &owner);
    id node = CFBridgingRelease(hit);
    if (owner != finderPID) return nil;

    for (int level = 0; node && level < 12; level++) {
        NSString *role = attribute(node, kAXRoleAttribute);
        // Container URLs may describe the open folder or the window proxy.
        if ([@[@"AXApplication", @"AXWindow", @"AXToolbar", @"AXScrollArea", @"AXList",
               @"AXOutline", @"AXTable", @"AXBrowser", @"AXCollectionList", @"AXSectionList",
               @"AXMenu", @"AXMenuBar"] containsObject:role ?: @""]) break;
        NSURL *url = itemURL(node);
        if (url) return url;
        if ([role isEqual:@"AXRow"] || [role isEqual:@"AXCell"] || [role isEqual:@"AXLayoutItem"]) {
            NSUInteger budget = 30;
            url = urlInRow(node, 3, &budget);
            if (url) return url;
        }
        node = attribute(node, kAXParentAttribute);
    }
    return nil;
}
