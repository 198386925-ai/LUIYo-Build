#import "LUISettingsHeroAdapter.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>
// Compatibility helpers live here; the supplied cell below remains byte-for-byte unchanged.
static UIColor *LUISettingsLiquidDynamicColor(UIColor *light, UIColor *dark) { return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) { return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light; }]; }
static UIColor *LUISettingsInkColor(void) { return UIColor.labelColor; }
static UIColor *LUISettingsInk2Color(void) { return UIColor.secondaryLabelColor; }
static UIColor *LUISettingsInk3Color(void) { return UIColor.tertiaryLabelColor; }
static UIColor *LUISettingsOnInkColor(void) { return LUISettingsLiquidDynamicColor(UIColor.whiteColor, UIColor.blackColor); }
static UIColor *LUISettingsControlTrackColor(void) { return UIColor.tertiarySystemFillColor; }
static UIColor *LUISettingsAccentColor(void) { return [UIColor colorWithRed:.69 green:.54 blue:.31 alpha:1]; }
static UIColor *LUISettingsBadgeBackgroundColor(void) { return [LUISettingsAccentColor() colorWithAlphaComponent:.12]; }
static UIColor *LUISettingsLiquidSwitchOnTintColor(void) { return UIColor.systemGreenColor; }
static BOOL LUISettingsLiquidTraitIsDark(UITraitCollection *t) { return t.userInterfaceStyle == UIUserInterfaceStyleDark; }
static void LUISettingsApplyTitleLabelChrome(UILabel *label) { label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = .85; }
static CGFloat LUISettingsSafeLineHeight(UIFont *font) { return font.lineHeight; }
static UIView *LUISettingsLiquidWrapSwitch(UISwitch *toggle) { UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0,0,44,26)]; toggle.transform = CGAffineTransformMakeScale(44.0/51.0,26.0/31.0); toggle.center = CGPointMake(22,13); [host addSubview:toggle]; return host; }
static UIImage *LUISettingsAvatarImage(void) { return nil; }
static BOOL LUIConfigBool(NSString *key, BOOL fallback) { id value = [NSUserDefaults.standardUserDefaults objectForKey:key]; return value ? [value boolValue] : fallback; }
static void LUIConfigSetBool(NSString *key, BOOL enabled) { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key]; }
static void LUISettingsApplyChangedKey(NSString *key) { [NSNotificationCenter.defaultCenter postNotificationName:@"LUIYoHeroPreferenceChanged" object:key]; }
static void LUISettingsNotifyValueChangedFromResponder(UIResponder *responder, NSString *key) { [NSNotificationCenter.defaultCenter postNotificationName:@"LUIYoHeroValueChanged" object:responder userInfo:@{@"key":key}]; }
static void LUISettingsApplyLiquidCardBackground(UITableViewCell *cell) { cell.backgroundColor = UIColor.clearColor; UIVisualEffectView *background = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]]; background.layer.cornerRadius = 24; background.clipsToBounds = YES; cell.backgroundView = background; }
#include "LUISettingsHeroCell.m"
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void)) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"luiyo.hero.enabled":@YES}];
    LUISettingsHeroCell *cell = [[LUISettingsHeroCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [cell configureWithTitle:@"LUIYo" version:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] key:@"luiyo.hero.enabled"];
    cell.onInfo = onInfo; cell.onChangelog = onChangelog;
    return cell;
}
