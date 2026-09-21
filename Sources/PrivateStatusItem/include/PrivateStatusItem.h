#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns a status item placed as far right as the system allows (just left of
/// the system items), using the private NSStatusBar API when available.
/// Returns nil when the private selector is unavailable, so the caller can fall
/// back to the public `statusItemWithLength:` API.
FOUNDATION_EXPORT NSStatusItem * _Nullable AIStatusItemWithPriority(CGFloat length, int32_t priority);

NS_ASSUME_NONNULL_END
