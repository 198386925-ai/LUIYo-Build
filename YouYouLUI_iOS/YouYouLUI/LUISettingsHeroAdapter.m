#import "LUISettingsHeroAdapter.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
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
static UIFont *_LUIYoHeroCustomFont = nil;
static UIFont *LUIYoLoadThemeFontFromDisk(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (paths.count == 0) return nil;
    NSString *fontPath = [paths[0] stringByAppendingPathComponent:@"ThemeFont.data"];
    NSData *data = [NSData dataWithContentsOfFile:fontPath];
    if (!data || data.length == 0) return nil;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (!provider) return nil;
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!cgFont) return nil;
    NSString *fontName = (__bridge_transfer NSString *)CGFontCopyPostScriptName(cgFont);
    CFErrorRef error = NULL;
    if (!CTFontManagerRegisterGraphicsFont(cgFont, &error)) {
        // Already registered, try to use it anyway
    }
    CGFontRelease(cgFont);
    if (!fontName) return nil;
    return [UIFont fontWithName:fontName size:16.0];
}
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font);
void LUIYoRefreshSettingsHero(UIView *view) {
    if (![view isKindOfClass:LUISettingsHeroCell.class]) return;
    LUISettingsHeroCell *cell = (LUISettingsHeroCell *)view;
    // Self-sufficient: load theme font from disk if not in memory (fixes instability)
    if (!_LUIYoHeroCustomFont) {
        _LUIYoHeroCustomFont = LUIYoLoadThemeFontFromDisk();
    }
    NSString *name = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.hero.name"] ?: @"LUIYo";
    NSString *shortVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.6";
    NSString *buildNum = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    NSString *version = [NSString stringWithFormat:@"Version%@ Build%@", shortVer, buildNum];
    [cell configureWithTitle:name version:version key:@"luiyo.hero.enabled"];
    // Use custom theme font if set, otherwise default system font.
    cell.nameLabel.font = _LUIYoHeroCustomFont ? [_LUIYoHeroCustomFont fontWithSize:18.0] : [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    cell.nameLabel.attributedText = nil;
    cell.nameLabel.text = name;
    cell.nameLabel.textColor = LUISettingsInkColor();
    cell.nameLabel.accessibilityValue = name;
    cell.versionChip.layer.cornerRadius = 9;
    // The app has its own appearance selector; UIKit's inherited trait can be stale
    // while a page transition is in progress. Resolve the hero from that explicit
    // preference first, and consult the live window trait only in System mode.
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.appearanceMode"] ?: @"system";
    BOOL useDark;
    if ([mode isEqualToString:@"light"]) useDark = NO;
    else if ([mode isEqualToString:@"dark"]) useDark = YES;
    else {
        UITraitCollection *traits = cell.window.traitCollection ?: cell.traitCollection;
        useDark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    NSString *appearance = useDark ? @"dark" : @"light";
    NSString *key = [@"youyou.heroCardColor." stringByAppendingString:appearance];
    NSString *savedHex = [NSUserDefaults.standardUserDefaults stringForKey:key];
    // A stale saved dark card color must never override explicit Light mode.
    NSString *hex = useDark ? (savedHex.length ? savedHex : @"#1C1C1E") : @"#FFFFFF";
    unsigned int value = 0;
    [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
    UIColor *resolved = [UIColor colorWithRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:((value)&255)/255.0 alpha:1];
    cell.backgroundView.backgroundColor = resolved;
    cell.overrideUserInterfaceStyle = useDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    [cell setNeedsLayout];
    // Re-apply custom theme font if one was set (refresh resets to system fonts).
    if (_LUIYoHeroCustomFont) LUIYoSetSettingsHeroFont(cell, _LUIYoHeroCustomFont);
}
/// Set a custom theme font on the hero's labels. Pass nil to revert to system fonts.
static void LUIYoSetHeroButtonFont(UIButton *button, UIFont *font) {
    // Skip if the font is already correct (avoid flicker from repeated rebuilds).
    UIFont *current = button.titleLabel.font;
    if (current && [current.fontName isEqualToString:font.fontName] && fabs(current.pointSize - font.pointSize) < 0.1) {
        return;
    }
    button.titleLabel.font = font;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = button.configuration;
        if (cfg) {
            // Rebuild attributedTitle with the new font, preserving the chevron.
            NSString *title = cfg.attributedTitle ? cfg.attributedTitle.string : [button titleForState:UIControlStateNormal];
            // Strip trailing chevron glyph if present (added as separate attribute).
            NSString *clean = [title stringByReplacingOccurrencesOfString:@" ›" withString:@""];
            NSMutableAttributedString *t = [[NSMutableAttributedString alloc]
                initWithString:[clean stringByAppendingString:@" ›"]
                attributes:@{NSFontAttributeName: font}];
            [t addAttributes:@{NSForegroundColorAttributeName: button.tintColor ?: UIColor.labelColor}
                       range:NSMakeRange(t.length - 1, 1)];
            cfg.attributedTitle = t;
            button.configuration = cfg;
        }
    }
}
void LUIYoSetSettingsHeroFont(UIView *view, UIFont * _Nullable font) {
    _LUIYoHeroCustomFont = font;
    if (![view isKindOfClass:LUISettingsHeroCell.class]) return;
    LUISettingsHeroCell *cell = (LUISettingsHeroCell *)view;
    if (font) {
        cell.nameLabel.font = [font fontWithSize:18.0];
        cell.versionChip.font = [font fontWithSize:10.5];
        cell.statusLabel.font = [font fontWithSize:11.0];
        cell.avatarGlyph.font = [font fontWithSize:21.0];
        LUIYoSetHeroButtonFont(cell.infoButton, [font fontWithSize:12.0]);
        LUIYoSetHeroButtonFont(cell.logButton, [font fontWithSize:12.0]);
    } else {
        cell.nameLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
        cell.versionChip.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium];
        cell.statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        cell.avatarGlyph.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightHeavy];
        LUIYoSetHeroButtonFont(cell.infoButton, [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]);
        LUIYoSetHeroButtonFont(cell.logButton, [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]);
    }
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
