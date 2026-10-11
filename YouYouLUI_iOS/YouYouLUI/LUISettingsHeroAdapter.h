#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void), void (^onAvatar)(void), void (^onName)(void));
void LUIYoRefreshSettingsHero(UIView *view);
NS_ASSUME_NONNULL_END
