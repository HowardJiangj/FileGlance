#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(id element, CFStringRef key) {
    CFTypeRef result = NULL;
    AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element, key, &result);
    return CFBridgingRelease(result);
}

static NSURL *fileURL(id value) {
    if ([value isKindOfClass:NSString.class]) {
        value = [value hasPrefix:@"/"] ? [NSURL fileURLWithPath:value] : [NSURL URLWithString:value];
    }
    if (![value isKindOfClass:NSURL.class] || ![value isFileURL]) return nil;
    NSURL *url = value;
    return url.isFileReferenceURL ? url.filePathURL : url;
}

static NSURL *itemURL(id node) {
    return fileURL(attribute(node, kAXURLAttribute));
}

// Some icon views expose a filename or display title without an AXURL.
static NSURL *iconFile(id icon) {
    id window = attribute(icon, kAXWindowAttribute);
    NSURL *folder = window ? fileURL(attribute(window, kAXDocumentAttribute)) : nil;
    if (!window) {
        folder = [NSFileManager.defaultManager URLsForDirectory:NSDesktopDirectory
                                                      inDomains:NSUserDomainMask].firstObject;
    }
    if (!folder) return nil;
    for (NSString *key in @[@"AXFilename", @"AXTitle", @"AXDescription"]) {
        NSString *name = attribute(icon, (__bridge CFStringRef)key);
        if (![name isKindOfClass:NSString.class] || !name.length ||
            ![name isEqual:name.lastPathComponent] || [name isEqual:@"."] || [name isEqual:@".."]) continue;
        NSURL *candidate = [folder URLByAppendingPathComponent:name];
        if ([candidate checkResourceIsReachableAndReturnError:nil]) return candidate;
        // Finder can omit the extension in its displayed title.
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder
            includingPropertiesForKeys:@[NSURLLocalizedNameKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        NSURL *match = nil;
        for (NSURL *file in files) {
            NSString *display = nil;
            [file getResourceValue:&display forKey:NSURLLocalizedNameKey error:nil];
            if (![display isEqual:name] && ![file.lastPathComponent.stringByDeletingPathExtension isEqual:name]) continue;
            if (match) return nil;
            match = file;
        }
        if (match) return match;
    }
    return nil;
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

    id icon = nil;
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
        if (!icon && ([role isEqual:@"AXImage"] || [role isEqual:@"AXLayoutItem"])) icon = node;
        node = attribute(node, kAXParentAttribute);
    }
    return icon ? iconFile(icon) : nil;
}
