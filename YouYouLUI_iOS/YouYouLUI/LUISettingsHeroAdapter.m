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
// The brand card is a normal painted card, independent of the app's glass theme.
@interface LUIYoHeroSwitchHost : UIControl
@property(nonatomic,strong) UISwitch *sourceSwitch;
@property(nonatomic,strong) UIView *track;
@property(nonatomic,strong) UIView *knob;
@property(nonatomic,strong) UIImageView *cloud;
@property(nonatomic,strong) UIImageView *moon;
@end
@implementation LUIYoHeroSwitchHost
- (instancetype)initWithSwitch:(UISwitch *)toggle {
    if (!(self = [super initWithFrame:CGRectMake(0,0,44,26)])) return nil;
    self.sourceSwitch = toggle; toggle.hidden = YES; [self addSubview:toggle];
    self.track = [UIView new]; self.track.userInteractionEnabled = NO; self.track.layer.cornerRadius = 10; self.track.layer.borderWidth = 1; [self addSubview:self.track];
    self.knob = [UIView new]; self.knob.userInteractionEnabled = NO; self.knob.layer.cornerRadius = 9; self.knob.layer.borderWidth = 1; [self.track addSubview:self.knob];
    self.cloud = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cloud.fill"]];self.cloud.tintColor = UIColor.whiteColor;self.cloud.contentMode = UIViewContentModeScaleAspectFit;[self.track addSubview:self.cloud];
    self.moon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"moon.fill"]];self.moon.tintColor = UIColor.whiteColor;self.moon.contentMode = UIViewContentModeScaleAspectFit;[self.knob addSubview:self.moon];
    [self addTarget:self action:@selector(toggleValue) forControlEvents:UIControlEventTouchUpInside];
    self.isAccessibilityElement = YES; self.accessibilityLabel = @"启用";self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)toggleValue { self.sourceSwitch.on = !self.sourceSwitch.on; [self.sourceSwitch sendActionsForControlEvents:UIControlEventValueChanged];[self setNeedsLayout]; }
- (BOOL)accessibilityActivate { [self toggleValue];return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];BOOL on = self.sourceSwitch.on;
    self.track.frame = CGRectMake(0,3,44,20);
    self.track.backgroundColor = on ? [UIColor colorWithRed:.65 green:.88 blue:.94 alpha:1] : [UIColor colorWithRed:.21 green:.24 blue:.38 alpha:1];
    self.track.layer.borderColor = [UIColor colorWithRed:.52 green:.73 blue:.79 alpha:1].CGColor;
    self.knob.frame = CGRectMake(on?24:2,1,18,18);
    self.knob.backgroundColor = on ? [UIColor colorWithRed:1 green:.87 blue:.39 alpha:1] : [UIColor colorWithRed:.46 green:.51 blue:.72 alpha:1];
    self.knob.layer.borderColor = [UIColor colorWithRed:.85 green:.74 blue:.38 alpha:1].CGColor;
    self.cloud.frame = CGRectMake(14,9,13,7);self.cloud.hidden = !on;
    self.moon.frame = CGRectMake(4,4,10,10);self.moon.hidden = on;
    self.accessibilityValue = on ? @"已启用" : @"未启用";
}
@end
UIControl *LUIYoCreateThemeSwitch(BOOL enabled, void (^onChange)(BOOL)) {
    UISwitch *source = [UISwitch new];source.on = enabled;
    [source addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { onChange(((UISwitch *)action.sender).on); }] forControlEvents:UIControlEventValueChanged];
    return [[LUIYoHeroSwitchHost alloc] initWithSwitch:source];
}
void LUIYoSetThemeSwitch(UIControl *view, BOOL enabled) {
    if (![view isKindOfClass:LUIYoHeroSwitchHost.class]) return;
    ((LUIYoHeroSwitchHost *)view).sourceSwitch.on = enabled;[view setNeedsLayout];
}
static UIView *LUISettingsLiquidWrapSwitch(UISwitch *toggle) { return [[LUIYoHeroSwitchHost alloc] initWithSwitch:toggle]; }
static NSURL *LUIYoHeroAvatarURL(void) { return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"SettingsAvatar.png"]; }
static UIImage *LUISettingsAvatarImage(void) {
    UIImage *saved = [UIImage imageWithContentsOfFile:LUIYoHeroAvatarURL().path];
    if (saved) return saved;
    UIImage *reference = [UIImage imageNamed:@"BrandReference"];
    if (!reference.CGImage) return nil;
    CGImageRef crop = CGImageCreateWithImageInRect(reference.CGImage, CGRectMake(108,88,144,148));
    if (!crop) return nil;
    UIImage *avatar = [UIImage imageWithCGImage:crop];CGImageRelease(crop);return avatar;
}
static BOOL LUIConfigBool(NSString *key, BOOL fallback) { id value = [NSUserDefaults.standardUserDefaults objectForKey:key]; return value ? [value boolValue] : fallback; }
static void LUIConfigSetBool(NSString *key, BOOL enabled) { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key]; }
static void LUISettingsApplyChangedKey(NSString *key) { [NSNotificationCenter.defaultCenter postNotificationName:@"LUIYoHeroPreferenceChanged" object:key]; }
static void LUISettingsNotifyValueChangedFromResponder(UIResponder *responder, NSString *key) { [NSNotificationCenter.defaultCenter postNotificationName:@"LUIYoHeroValueChanged" object:responder userInfo:@{@"key":key}]; }
static void LUISettingsApplyLiquidCardBackground(UITableViewCell *cell) {
    cell.backgroundColor = UIColor.clearColor;
    UIView *background = [UIView new];background.backgroundColor = LUISettingsLiquidDynamicColor([UIColor colorWithWhite:.99 alpha:1],[UIColor colorWithWhite:.13 alpha:1]);background.layer.cornerRadius = 24;background.clipsToBounds = YES;cell.backgroundView = background;
}
#include "LUISettingsHeroCell.m"
@interface LUIYoEditableHeroCell : LUISettingsHeroCell
@property(nonatomic,copy) void (^onAvatar)(void);
@property(nonatomic,copy) void (^onName)(void);
@end
@implementation LUIYoEditableHeroCell
- (void)editAvatar { if (self.onAvatar) self.onAvatar(); }
- (void)editName { if (self.onName) self.onName(); }
@end
void LUIYoRefreshSettingsHero(UIView *view) {
    if (![view isKindOfClass:LUISettingsHeroCell.class]) return;
    LUISettingsHeroCell *cell = (LUISettingsHeroCell *)view;
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.hero.name"] ?: @"Liquid UI";
    NSString *version = [@"Version " stringByAppendingString:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.6"];
    [cell configureWithTitle:name version:version key:@"luiyo.hero.enabled"];
    cell.nameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    cell.nameLabel.attributedText = [[NSAttributedString alloc] initWithString:name attributes:@{NSFontAttributeName:cell.nameLabel.font,NSStrokeColorAttributeName:LUISettingsInkColor(),NSStrokeWidthAttributeName:@1.8}];
    cell.nameLabel.accessibilityValue = name;
    cell.versionChip.layer.cornerRadius = 9;
    UIColor *fill = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        NSString *appearance = traits.userInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : @"light";
        NSString *key = [@"youyou.heroCardColor." stringByAppendingString:appearance];
        NSString *savedHex = [NSUserDefaults.standardUserDefaults stringForKey:key];
        // Prevent a stale dark-theme preference from turning the authorization
        // hero charcoal while the Settings page is in light appearance.
        NSString *hex = [appearance isEqualToString:@"dark"]
            ? (savedHex.length ? savedHex : @"#1C1C1E")
            : @"#FFFFFF";
        unsigned int value = 0;[[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
        return [UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1];
    }];
    UIColor *resolved = [fill resolvedColorWithTraitCollection:cell.superview.traitCollection ?: cell.traitCollection];
    cell.backgroundView.backgroundColor = resolved;
    CGFloat red=1,green=1,blue=1,alpha=1;[resolved getRed:&red green:&green blue:&blue alpha:&alpha];
    BOOL darkInk = .2126*red + .7152*green + .0722*blue > .5;
    cell.overrideUserInterfaceStyle = darkInk ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    [cell setNeedsLayout];
}
UIView *LUIYoCreateSettingsHero(void (^onInfo)(void), void (^onChangelog)(void), void (^onAvatar)(void), void (^onName)(void)) {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"luiyo.hero.enabled":@YES}];
    LUIYoEditableHeroCell *cell = [[LUIYoEditableHeroCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.onInfo = onInfo;cell.onChangelog = onChangelog;cell.onAvatar = onAvatar;cell.onName = onName;
    cell.avatarView.userInteractionEnabled = YES;cell.avatarView.accessibilityLabel = @"更换头像";cell.avatarView.accessibilityTraits = UIAccessibilityTraitButton;cell.avatarView.isAccessibilityElement = YES;
    [cell.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:cell action:@selector(editAvatar)]];
    cell.nameLabel.userInteractionEnabled = YES;cell.nameLabel.accessibilityLabel = @"修改名字";cell.nameLabel.accessibilityTraits = UIAccessibilityTraitButton;
    [cell.nameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:cell action:@selector(editName)]];
    LUIYoRefreshSettingsHero(cell);
    return cell;
}
