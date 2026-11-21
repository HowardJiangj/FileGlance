#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "HoverCard.h"

extern NSURL *FinderFileAtPoint(CGPoint point, pid_t finderPID);

@interface GlanceApp : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *item;
@property (strong) HoverCard *card;
@property (strong) NSMenuItem *stateItem, *toggleItem;
@property (strong) NSTimer *timer;
@property (strong) dispatch_queue_t finderQueue;
@property NSPoint anchor;
@property NSTimeInterval nextCheck, permissionCheck;
@property NSUInteger generation;
@property BOOL paused, trusted, querying, menuOpen;
@end

@implementation GlanceApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.finderQueue = dispatch_queue_create("local.fileglance.hover", DISPATCH_QUEUE_SERIAL);
    self.card = [HoverCard new];
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *symbol = nil;
    if (@available(macOS 11, *)) symbol = [NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"FileGlance"];
    if (symbol) self.item.button.image = symbol;
    else self.item.button.title = @"览";
    self.item.button.toolTip = @"FileGlance · 文件悬停预览";
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    self.stateItem = [menu addItemWithTitle:@"FileGlance" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    self.toggleItem = [menu addItemWithTitle:@"暂停悬停预览" action:@selector(toggle:) keyEquivalent:@""];
    self.toggleItem.target = self;
    [menu addItemWithTitle:@"辅助功能权限…" action:@selector(settings:) keyEquivalent:@""].target = self;
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"退出FileGlance" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
    self.item.menu = menu;
    self.trusted = AXIsProcessTrusted();
    [self updateStatus];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tick:)
        userInfo:nil repeats:YES];
    self.timer.tolerance = 0.02;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceChanged:)
        name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceChanged:)
        name:NSWorkspaceDidActivateApplicationNotification object:nil];
    if (!self.trusted) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"让FileGlance识别指针下的文件";
        alert.informativeText = @"请在“辅助功能”中允许“FileGlance”。开启后，把鼠标停在访达或桌面的文件上约半秒，即可看到文件信息和预览。菜单栏的眼睛图标可暂停或退出FileGlance。";
        [alert addButtonWithTitle:@"打开辅助功能设置"];
        [alert addButtonWithTitle:@"稍后"];
        [NSApp activateIgnoringOtherApps:YES];
        if ([alert runModal] == NSAlertFirstButtonReturn) [self settings:nil];
    }
}
- (void)settings:(id)sender {
    if (!AXIsProcessTrusted()) {
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    }
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)updateStatus {
    self.stateItem.title = !self.trusted ? @"FileGlance · 等待辅助功能权限" : self.paused ? @"FileGlance · 已暂停" : @"FileGlance · 悬停预览已开启";
    self.toggleItem.title = self.paused ? @"恢复悬停预览" : @"暂停悬停预览";
}
- (void)resetHover {
    self.generation++;
    self.anchor = NSEvent.mouseLocation;
    self.nextCheck = NSProcessInfo.processInfo.systemUptime + 0.55;
    [self.card hide];
}
- (void)toggle:(id)sender {
    self.paused = !self.paused;
    [self resetHover];
    [self updateStatus];
}
- (void)menuWillOpen:(NSMenu *)menu { self.menuOpen = YES; [self resetHover]; }
- (void)menuDidClose:(NSMenu *)menu { self.menuOpen = NO; [self resetHover]; }
- (void)workspaceChanged:(NSNotification *)note { [self resetHover]; }
- (void)tick:(NSTimer *)timer {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now >= self.permissionCheck) {
        self.permissionCheck = now + 2;
        BOOL trusted = AXIsProcessTrusted();
        if (trusted != self.trusted) {
            self.trusted = trusted;
            [self resetHover];
            [self updateStatus];
        }
    }
    if (self.paused || self.menuOpen || !self.trusted) return;
    NSPoint point = NSEvent.mouseLocation;
    if (!NSEqualPoints(point, self.anchor) || NSEvent.pressedMouseButtons != 0) {
        [self resetHover];
        return;
    }
    if (self.querying || now < self.nextCheck || !NSScreen.screens.count) return;
    self.nextCheck = now + 0.8;
    self.querying = YES;
    NSUInteger generation = self.generation;
    pid_t finder = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject.processIdentifier;
    CGPoint axPoint = CGPointMake(point.x, NSMaxY(NSScreen.screens.firstObject.frame) - point.y);
    dispatch_async(self.finderQueue, ^{
        NSURL *url = FinderFileAtPoint(axPoint, finder);
        FilePreview *file = url ? [FilePreview readInfo:url] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.querying = NO;
            if (generation != self.generation || !NSEqualPoints(point, NSEvent.mouseLocation) || NSEvent.pressedMouseButtons) return;
            if (file) [self.card showFile:file nearPoint:point];
            else [self.card hide];
        });
    });
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) GlanceApp *delegate = [GlanceApp new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
