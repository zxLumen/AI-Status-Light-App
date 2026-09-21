#import "PrivateStatusItem.h"
#import <objc/message.h>

NSStatusItem * _Nullable AIStatusItemWithPriority(CGFloat length, int32_t priority) {
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    SEL sel = NSSelectorFromString(@"_statusItemWithLength:withPriority:");
    if (![bar respondsToSelector:sel]) {
        return nil;
    }
    // The priority parameter is a 32-bit int; using NSInteger here would pass the
    // wrong low word (INT64_MAX truncates to -1) and place the item far left.
    NSStatusItem *(*send)(id, SEL, CGFloat, int) =
        (NSStatusItem *(*)(id, SEL, CGFloat, int))objc_msgSend;
    return send(bar, sel, length, (int)priority);
}
