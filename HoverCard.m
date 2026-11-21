#import "HoverCard.h"
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>

@interface HoverCard ()
@property (strong) NSPanel *panel;
@property (strong) NSImageView *image;
@property (strong) NSTextField *excerpt, *name, *size;
@property (strong) FilePreview *current;
@property (strong) QLThumbnailGenerationRequest *request;
@property (strong) NSOperationQueue *worker;
@end

@implementation HoverCard
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.worker = [NSOperationQueue new];
    self.worker.maxConcurrentOperationCount = 1;
    self.worker.qualityOfService = NSQualityOfServiceUserInitiated;
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,288,224)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:NO];
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.ignoresMouseEvents = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.level = NSPopUpMenuWindowLevel;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;
    NSVisualEffectView *base = [[NSVisualEffectView alloc] initWithFrame:self.panel.contentView.bounds];
    base.material = NSVisualEffectMaterialPopover;
    base.state = NSVisualEffectStateActive;
    base.wantsLayer = YES;
    base.layer.cornerRadius = 14;
    base.layer.masksToBounds = YES;
    self.panel.contentView = base;
    NSBox *well = [[NSBox alloc] initWithFrame:NSMakeRect(8,70,272,146)];
    well.boxType = NSBoxCustom;
    well.borderWidth = 0;
    well.cornerRadius = 8;
    well.fillColor = [NSColor.labelColor colorWithAlphaComponent:0.055];
    well.autoresizingMask = NSViewMinYMargin;
    [base addSubview:well];
    self.image = [[NSImageView alloc] initWithFrame:NSMakeRect(14,76,260,134)];
    self.image.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.image.autoresizingMask = NSViewMinYMargin;
    [base addSubview:self.image];
    self.excerpt = [NSTextField wrappingLabelWithString:@""];
    self.excerpt.frame = NSMakeRect(20,82,248,119);
    self.excerpt.maximumNumberOfLines = 7;
    self.excerpt.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.excerpt.lineBreakMode = NSLineBreakByWordWrapping;
    self.excerpt.autoresizingMask = NSViewMinYMargin;
    [base addSubview:self.excerpt];
    self.name = [NSTextField wrappingLabelWithString:@""];
    self.name.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    self.name.frame = NSMakeRect(14,28,260,37);
    self.name.maximumNumberOfLines = 0;
    self.name.lineBreakMode = NSLineBreakByCharWrapping;
    [base addSubview:self.name];
    self.size = [NSTextField labelWithString:@""];
    self.size.frame = NSMakeRect(14,9,260,17);
    self.size.textColor = NSColor.secondaryLabelColor;
    self.size.font = [NSFont systemFontOfSize:12];
    [base addSubview:self.size];
    return self;
}

- (void)hide {
    if (self.request) [[QLThumbnailGenerator sharedGenerator] cancelRequest:self.request];
    self.request = nil;
    [self.worker cancelAllOperations];
    self.current = nil;
    [self.panel orderOut:nil];
}

- (void)showFile:(FilePreview *)file nearPoint:(NSPoint)point {
    if ([self.current.url isEqual:file.url] && [self.current.modified isEqual:file.modified] &&
        [self.current.sizeText isEqual:file.sizeText] && self.current.localContent == file.localContent) return;
    [self hide];
    self.current = file;
    self.name.stringValue = file.url.lastPathComponent;
    CGFloat nameHeight = ceil([self.name.cell cellSizeForBounds:NSMakeRect(0,0,260,4096)].height);
    nameHeight = MAX(18, nameHeight);
    [self.panel setContentSize:NSMakeSize(288,187 + nameHeight)];
    self.name.frame = NSMakeRect(14,28,260,nameHeight);
    self.size.stringValue = file.sizeText;
    self.excerpt.hidden = YES;
    self.excerpt.stringValue = @"";
    self.image.hidden = NO;
    self.image.imageScaling = NSImageScaleProportionallyDown;
    NSImage *icon = [[NSWorkspace.sharedWorkspace iconForFile:file.url.path] copy];
    icon.size = NSMakeSize(62,62);
    self.image.image = icon;
    NSScreen *screen = nil;
    for (NSScreen *s in NSScreen.screens) if (NSPointInRect(point, s.frame)) { screen = s; break; }
    if (!screen) { [self hide]; return; }
    NSRect area = NSInsetRect(screen.visibleFrame, 5, 5);
    NSSize size = self.panel.frame.size;
    CGFloat x = point.x + 16, y = point.y - size.height - 12;
    if (x + size.width > NSMaxX(area)) x = point.x - size.width - 16;
    if (y < NSMinY(area)) y = point.y + 16;
    [self.panel setFrameOrigin:NSMakePoint(MAX(NSMinX(area),MIN(x, NSMaxX(area)-size.width)),
                                         MAX(NSMinY(area),MIN(y,NSMaxY(area)-size.height)))];
    [self.panel orderFrontRegardless];
    if (!file.localContent) return;
    [self.worker addOperationWithBlock:^{
        NSImage *image = [file imagePreview];
        NSString *text = image ? nil : [file textPreview];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.current != file) return;
            if (image) {
                self.image.imageScaling = NSImageScaleProportionallyUpOrDown;
                self.image.image = image;
            } else if (text) {
                self.image.hidden = YES;
                self.excerpt.hidden = NO;
                self.excerpt.stringValue = text;
            } else {
                self.request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:file.url
                    size:CGSizeMake(260,134) scale:screen.backingScaleFactor
                    representationTypes:QLThumbnailGenerationRequestRepresentationTypeThumbnail];
                [[QLThumbnailGenerator sharedGenerator] generateBestRepresentationForRequest:self.request
                    completionHandler:^(QLThumbnailRepresentation *rep, NSError * __unused error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.current != file) return;
                        if (rep) {
                            self.image.imageScaling = NSImageScaleProportionallyUpOrDown;
                            self.image.image = rep.NSImage;
                        }
                        self.request = nil;
                    });
                }];
            }
        });
    }];
}
@end
