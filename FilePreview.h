#import <AppKit/AppKit.h>
@interface FilePreview : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *sizeText;
@property (nonatomic, strong) NSDate *modified;
@property (nonatomic, copy) NSString *kindText;
@property BOOL localContent;
+ (instancetype)readInfo:(NSURL *)url;
- (NSImage *)imagePreview;
- (NSString *)textPreview;
@end
