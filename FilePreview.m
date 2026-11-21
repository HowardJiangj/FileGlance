#import "FilePreview.h"
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

// Avoid depending on a thumbnail provider or opening the file to describe it.
static NSString *fileKind(NSURL *url, BOOL package, BOOL link) {
    if (link) return @"Symbolic link";
    NSString *ext = url.pathExtension.lowercaseString;
    NSString *type = nil;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:nil];
    if (!type && ext.length) {
        type = CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
            (__bridge CFStringRef)ext, NULL));
    }
    if (package) return [ext isEqual:@"app"] ? @"macOS application" : @"File package";
    if ([ext isEqual:@"pdf"]) return @"PDF document";
    NSString *category = nil;
    if (type) {
        CFStringRef uti = (__bridge CFStringRef)type;
        if (UTTypeConformsTo(uti, kUTTypeImage)) category = @"image";
        else if (UTTypeConformsTo(uti, kUTTypeAudio)) category = @"audio";
        else if (UTTypeConformsTo(uti, kUTTypeMovie)) category = @"video";
        else if (UTTypeConformsTo(uti, kUTTypeArchive)) category = @"archive";
        else if (UTTypeConformsTo(uti, kUTTypeSpreadsheet)) category = @"spreadsheet";
        else if (UTTypeConformsTo(uti, kUTTypePresentation)) category = @"presentation";
        else if (UTTypeConformsTo(uti, kUTTypeSourceCode)) category = @"source code";
        else if (UTTypeConformsTo(uti, kUTTypeText)) category = @"text document";
    }
    if (!category) {
        // Office types and other app-defined formats may only conform to public.data.
        static NSDictionary<NSString *, NSString *> *kinds;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            kinds = @{@"docx": @"Word document", @"doc": @"Word document",
                      @"xlsx": @"spreadsheet", @"xls": @"spreadsheet", @"csv": @"table",
                      @"pptx": @"presentation", @"ppt": @"presentation",
                      @"zip": @"archive", @"7z": @"archive", @"rar": @"archive",
                      @"gz": @"archive", @"tar": @"archive", @"dmg": @"disk image",
                      @"png": @"image", @"jpg": @"image", @"jpeg": @"image", @"heic": @"image",
                      @"mp3": @"audio", @"wav": @"audio", @"m4a": @"audio",
                      @"mp4": @"video", @"mov": @"video", @"mkv": @"video",
                      @"txt": @"text document", @"md": @"Markdown document",
                      @"json": @"data file", @"psd": @"Photoshop document",
                      @"ai": @"Illustrator document"};
        });
        category = kinds[ext];
    }
    if (ext.length) return [NSString stringWithFormat:@"%@ %@", ext.uppercaseString, category ?: @"file"];
    return category.capitalizedString ?: @"File without an extension";
}

@implementation FilePreview
+ (instancetype)readInfo:(NSURL *)url {
    if (!url.isFileURL) return nil;
    struct stat info;
    if (lstat(url.fileSystemRepresentation, &info) != 0) return nil;
    BOOL package = S_ISDIR(info.st_mode) && [NSWorkspace.sharedWorkspace isFilePackageAtPath:url.path];
    if (!S_ISREG(info.st_mode) && !S_ISLNK(info.st_mode) && !package) return nil;
    FilePreview *file = [self new];
    file.url = url;
    file.kindText = fileKind(url, package, S_ISLNK(info.st_mode));
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    formatter.allowsNonnumericFormatting = NO;
    formatter.includesUnit = NO;
    // Use explicit English unit names even when macOS uses another language.
    NSArray *units = @[@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB"];
    NSUInteger unit = 0;
    unsigned long long amount = info.st_size;
    while (amount >= 1000 && unit + 1 < units.count) { amount /= 1000; unit++; }
    formatter.allowedUnits = 1UL << unit;
    file.sizeText = [NSString stringWithFormat:@"%@ %@", [formatter stringFromByteCount:info.st_size],
                     info.st_size == 1 ? @"byte" : units[unit]];
    if (package) file.sizeText = @""; // Directory entry size is not the size of its contents.
    file.modified = [NSDate dateWithTimeIntervalSince1970:info.st_mtimespec.tv_sec + info.st_mtimespec.tv_nsec / 1e9];
    NSString *download = nil;
    [url getResourceValue:&download forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
    file.localContent = S_ISREG(info.st_mode) && !(info.st_flags & SF_DATALESS) &&
        ![download isEqual:NSURLUbiquitousItemDownloadingStatusNotDownloaded];
    return file;
}

- (BOOL)isType:(CFStringRef)type {
    NSString *uti = nil;
    [self.url getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:nil];
    if (uti && UTTypeConformsTo((__bridge CFStringRef)uti, type)) return YES;
    NSString *ext = self.url.pathExtension.lowercaseString;
    if (CFEqual(type, kUTTypePDF)) return [ext isEqual:@"pdf"];
    if (CFEqual(type, kUTTypeImage)) {
        return [@[@"jpg", @"jpeg", @"png", @"gif", @"tif", @"tiff", @"heic", @"heif",
                  @"bmp", @"webp", @"avif", @"ico"] containsObject:ext];
    }
    return CFEqual(type, kUTTypePlainText) &&
        [@[@"txt", @"md", @"log", @"csv", @"json", @"xml", @"yaml", @"yml", @"ini",
           @"c", @"h", @"m", @"swift", @"py", @"js", @"css", @"html", @"sh"] containsObject:ext];
}

- (NSImage *)imagePreview {
    if (!self.localContent) return nil;
    if ([self isType:kUTTypeImage]) {
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)self.url, NULL);
        if (!source) return nil;
        NSDictionary *options = @{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                  (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                  (id)kCGImageSourceThumbnailMaxPixelSize:@640};
        CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
        CFRelease(source);
        if (!cg) return nil;
        NSImage *image = [[NSImage alloc] initWithCGImage:cg size:NSZeroSize];
        CGImageRelease(cg);
        return image;
    }
    if (![self isType:kUTTypePDF]) return nil;
    CGPDFDocumentRef pdf = CGPDFDocumentCreateWithURL((__bridge CFURLRef)self.url);
    if (!pdf) return nil;
    CGPDFPageRef page = CGPDFDocumentGetPage(pdf, 1);
    NSImage *image = nil;
    if (page) {
        CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
        if (CGPDFPageGetRotationAngle(page) % 180 != 0) box.size = CGSizeMake(box.size.height, box.size.width);
        CGFloat longest = MAX(box.size.width, box.size.height);
        if (isfinite(longest) && longest > 0) {
            size_t w = MAX(1, round(640 * box.size.width / longest));
            size_t h = MAX(1, round(640 * box.size.height / longest));
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if (ctx) {
                CGRect frame = CGRectMake(0, 0, w, h);
                CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
                CGContextFillRect(ctx, frame);
                CGContextConcatCTM(ctx, CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, frame, 0, true));
                CGContextDrawPDFPage(ctx, page);
                CGImageRef cg = CGBitmapContextCreateImage(ctx);
                if (cg) {
                    image = [[NSImage alloc] initWithCGImage:cg size:NSZeroSize];
                    CGImageRelease(cg);
                }
                CGContextRelease(ctx);
            }
        }
    }
    CGPDFDocumentRelease(pdf);
    return image;
}

- (NSString *)textPreview {
    if (!self.localContent || ![self isType:kUTTypePlainText]) return nil;
    int fd = open(self.url.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW);
    if (fd < 0) return nil;
    char buf[8192];
    ssize_t count = read(fd, buf, sizeof(buf));
    close(fd);
    if (count < 0) return nil;
    if (!count) return @"(Empty text)";
    const unsigned char *bytes = (const unsigned char *)buf;
    BOOL utf16 = count >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
                                 (bytes[0] == 0xfe && bytes[1] == 0xff));
    if (!utf16 && memchr(buf, 0, count)) return nil;
    // A bounded prefix can end halfway through the last character.
    for (NSInteger trim = 0; trim <= (count == sizeof(buf) ? 3 : 0); trim++) {
        NSString *s = [[NSString alloc] initWithBytes:buf length:count-trim
            encoding:utf16 ? NSUnicodeStringEncoding : NSUTF8StringEncoding];
        if (s) return s;
    }
    return nil;
}
@end
