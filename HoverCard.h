#import "FilePreview.h"
@interface HoverCard : NSObject
- (void)showFile:(FilePreview *)file nearPoint:(NSPoint)point;
- (void)hide;
@end
