// ============================================================================
// LUISettingsHeroCell.m — 一级页品牌卡（v3 墨玉 · 2026-09-20 用户拍板）
// 116pt · r24：左 48 圆头像（当前微信账号头像，LUISettingsAvatarImage；取不到时回落石墨底「L」字标，深色反转雾白）+ 3pt 外环；中 名字 20/700 + 两枚胶囊（等宽版本号、
// 砂金点「已启用」）；右 总开关（TUTKeyPluginEnabled，同 SwitchCell 落盘口径）；底部两枚 28pt 玻璃按钮
// 「插件信息 ›」「更新日志 ›」——把此前 profile 行的点按目标与顶栏感叹号都收进来。
// 装饰：右上一组墨色同心水纹（1pt · 9%）+ 左上到右下一道白 55%→0 斜向高光，尾端极淡砂金。
// 设计稿：~/Desktop/LiquidUI设置页重设计_2026-09-20/设计稿-LiquidUI设置页重设计.html §组件解剖。
// ============================================================================

static const CGFloat LUISettingsHeroHeight = 116.0;
static const CGFloat LUISettingsHeroRadius = 24.0;

@interface LUISettingsHeroCell : UITableViewCell
@property(nonatomic, copy) NSString *key;
@property(nonatomic, strong) CAGradientLayer *sheenLayer;
@property(nonatomic, strong) CAShapeLayer *rippleLayer;
@property(nonatomic, strong) UIView *avatarView;
@property(nonatomic, strong) UIImageView *avatarImageView;   // 微信头像（取到时盖住字标）
@property(nonatomic, strong) UILabel *avatarGlyph;           // 「L」字标兜底
@property(nonatomic, strong) CAShapeLayer *avatarRing;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *versionChip;
@property(nonatomic, strong) UIView *statusChip;
@property(nonatomic, strong) UIView *statusDot;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UISwitch *toggle;
@property(nonatomic, strong) UIView *toggleHost;
@property(nonatomic, strong) UIButton *infoButton;
@property(nonatomic, strong) UIButton *logButton;
@property(nonatomic, copy) void (^onInfo)(void);
@property(nonatomic, copy) void (^onChangelog)(void);
- (void)configureWithTitle:(NSString *)title version:(NSString *)version key:(NSString *)key;
@end

@implementation LUISettingsHeroCell

/// 玻璃卡按品牌卡半径裁（LUISettingsLiquidCornerSpecForView 读此选择器）。
- (CGFloat)lui_liquidCardCornerRadius { return LUISettingsHeroRadius; }

static UIButton *LUISettingsHeroMakeButton(NSString *symbol, NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = [UIButtonConfiguration plainButtonConfiguration];
        UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:12.0 weight:UIImageSymbolWeightMedium];
        cfg.image = [UIImage systemImageNamed:symbol withConfiguration:sym];
        cfg.imagePadding = 6.0;
        cfg.imagePlacement = NSDirectionalRectEdgeLeading;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(0, 10.0, 0, 11.0);
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:[title stringByAppendingString:@"  ›"]
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold]}];
        [t addAttributes:@{NSForegroundColorAttributeName: LUISettingsInk3Color()} range:NSMakeRange(t.length - 1, 1)];
        cfg.attributedTitle = t;
        cfg.baseForegroundColor = LUISettingsInkColor();
        // Transparent config background so liquid glass behind the control shows through.
        cfg.background.backgroundColor = [UIColor clearColor];
        b.configuration = cfg;
    } else {
        [b setTitle:title forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
        [b setTitleColor:LUISettingsInkColor() forState:UIControlStateNormal];
    }
    b.tintColor = LUISettingsInkColor();
    b.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) b.layer.cornerCurve = kCACornerCurveContinuous;
    b.clipsToBounds = YES;
    b.backgroundColor = [UIColor clearColor];
    b.layer.borderWidth = 0;

    // Liquid glass surface (iOS 26+ UIGlassEffect via runtime; else systemMaterial blur).
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) {
        Class glassCls = NSClassFromString(@"UIGlassEffect");
        if (glassCls) {
            effect = [[glassCls alloc] init];
        }
    }
    if (!effect) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.userInteractionEnabled = NO;
    glass.layer.cornerRadius = 14.0;
    if (@available(iOS 13.0, *)) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    glass.tag = 90210; // layout marker
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b insertSubview:glass atIndex:0];
    return b;
}

static UILabel *LUISettingsHeroMakeChipLabel(UIFont *font) {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = LUISettingsInk2Color();
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 9.0;
    l.clipsToBounds = YES;
    l.backgroundColor = LUISettingsControlTrackColor();
    LUISettingsApplyTitleLabelChrome(l);
    return l;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = LUISettingsHeroRadius;
    if (@available(iOS 13.0, *)) self.contentView.layer.cornerCurve = kCACornerCurveContinuous;

    // 斜向高光：白 55% → 0（42%）→ 砂金 8% 收尾。
    _sheenLayer = [CAGradientLayer layer];
    _sheenLayer.startPoint = CGPointMake(0.0, 0.0);
    _sheenLayer.endPoint = CGPointMake(1.0, 1.0);
    _sheenLayer.locations = @[@0.0, @0.42, @1.0];
    [self.contentView.layer addSublayer:_sheenLayer];

    // 同心水纹：4 圈 1pt，右上出画。
    _rippleLayer = [CAShapeLayer layer];
    _rippleLayer.fillColor = UIColor.clearColor.CGColor;
    _rippleLayer.lineWidth = 1.0;
    [self.contentView.layer addSublayer:_rippleLayer];

    _avatarView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48.0, 48.0)];
    _avatarView.layer.cornerRadius = 24.0;
    _avatarView.clipsToBounds = NO;
    _avatarGlyph = [[UILabel alloc] initWithFrame:_avatarView.bounds];
    _avatarGlyph.text = @"L";
    _avatarGlyph.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightHeavy];
    _avatarGlyph.textAlignment = NSTextAlignmentCenter;
    _avatarGlyph.textColor = LUISettingsOnInkColor();
    _avatarGlyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_avatarView addSubview:_avatarGlyph];
    // 微信头像自己裁圆（avatarView 不裁，外环 layer 出界 3pt）；aspectFill 铺满 48 圆。
    _avatarImageView = [[UIImageView alloc] initWithFrame:_avatarView.bounds];
    _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarImageView.clipsToBounds = YES;
    _avatarImageView.layer.cornerRadius = 24.0;
    _avatarImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _avatarImageView.hidden = YES;
    [_avatarView addSubview:_avatarImageView];
    _avatarRing = [CAShapeLayer layer];
    _avatarRing.fillColor = UIColor.clearColor.CGColor;
    _avatarRing.lineWidth = 1.0;
    _avatarRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(_avatarView.bounds, -3.0, -3.0)].CGPath;
    [_avatarView.layer addSublayer:_avatarRing];
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    _nameLabel.textColor = LUISettingsInkColor();
    LUISettingsApplyTitleLabelChrome(_nameLabel);
    [self.contentView addSubview:_nameLabel];

    _versionChip = LUISettingsHeroMakeChipLabel([UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightMedium]);
    [self.contentView addSubview:_versionChip];

    _statusChip = [[UIView alloc] initWithFrame:CGRectZero];
    _statusChip.layer.cornerRadius = 9.0;
    _statusChip.clipsToBounds = YES;
    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(8.0, 6.0, 6.0, 6.0)];
    _statusDot.layer.cornerRadius = 3.0;
    [_statusChip addSubview:_statusDot];
    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    LUISettingsApplyTitleLabelChrome(_statusLabel);
    [_statusChip addSubview:_statusLabel];
    [self.contentView addSubview:_statusChip];

    _toggle = [UISwitch new];
    _toggle.onTintColor = LUISettingsLiquidSwitchOnTintColor();
    [_toggle addTarget:self action:@selector(lui_toggleChanged:) forControlEvents:UIControlEventValueChanged];
    _toggleHost = LUISettingsLiquidWrapSwitch(_toggle);
    [self.contentView addSubview:_toggleHost];

    _infoButton = LUISettingsHeroMakeButton(@"info.circle", @"插件信息");
    [_infoButton addTarget:self action:@selector(lui_infoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_infoButton];
    _logButton = LUISettingsHeroMakeButton(@"list.bullet.rectangle", @"更新日志");
    [_logButton addTarget:self action:@selector(lui_logTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:_logButton];

    [self lui_refreshDecorColors];
    return self;
}

- (void)lui_refreshDecorColors {
    BOOL dark = LUISettingsLiquidTraitIsDark(self.traitCollection);
    UIColor *sheenA = [UIColor colorWithWhite:1.0 alpha:dark ? 0.10 : 0.55];
    UIColor *sheenB = [UIColor colorWithWhite:1.0 alpha:0.0];
    UIColor *gold = dark ? [UIColor colorWithRed:0.788 green:0.639 blue:0.416 alpha:0.10]
                         : [UIColor colorWithRed:0.690 green:0.541 blue:0.306 alpha:0.08];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.sheenLayer.colors = @[(id)sheenA.CGColor, (id)sheenB.CGColor, (id)gold.CGColor];
    self.rippleLayer.strokeColor = (dark ? [UIColor colorWithWhite:1.0 alpha:0.10]
                                         : [UIColor colorWithRed:0.106 green:0.114 blue:0.129 alpha:0.09]).CGColor;
    self.avatarRing.strokeColor = (dark ? [UIColor colorWithWhite:1.0 alpha:0.20]
                                        : [UIColor colorWithRed:0.106 green:0.114 blue:0.129 alpha:0.18]).CGColor;
    [CATransaction commit];
    // 头像：浅色石墨渐变底 + 暖纸字；深色雾白底 + 石墨字（LUISettingsOnInkColor 已是动态）。
    self.avatarView.backgroundColor = dark ? [UIColor colorWithRed:0.90 green:0.89 blue:0.87 alpha:1.0]
                                           : [UIColor colorWithRed:0.12 green:0.13 blue:0.15 alpha:1.0];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([previousTraitCollection hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection]) {
            [self lui_refreshDecorColors];
        }
    }
}

- (void)configureWithTitle:(NSString *)title version:(NSString *)version key:(NSString *)key {
    // 【液态重设计】品牌卡同走玻璃卡（不经 ApplyCellChrome，需单独挂）。
    LUISettingsApplyLiquidCardBackground(self);
    self.contentView.backgroundColor = UIColor.clearColor;
    self.key = key;
    // 顶部品牌卡：硬编码 LUIYo，版本胶囊显示会员等级 · 设备码（无皇冠）
    self.nameLabel.text = @"LUIYo";
    NSString *_tier = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.auth.tier"] ?: @"free";
    NSString *_tname = @"免费用户";
    if ([_tier isEqualToString:@"vip"]) _tname = @"普通会员";
    else if ([_tier isEqualToString:@"svip"]) _tname = @"SVIP会员";
    NSString *_dcode = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.device.code"];
    if (!_dcode || _dcode.length == 0) {
        NSString *_uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString *_sid = [[_uuid stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:6];
        _dcode = [NSString stringWithFormat:@"D-%@", [_sid uppercaseString]];
    }
    self.versionChip.text = [NSString stringWithFormat:@"%@ · %@", _tname, _dcode];
    self.versionChip.hidden = NO;
    // 颜色：未授权灰色，会员金色
    if ([_tier isEqualToString:@"free"]) {
        self.versionChip.backgroundColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0];
        self.versionChip.textColor = [UIColor colorWithRed:0.45 green:0.45 blue:0.48 alpha:1.0];
    } else {
        self.versionChip.backgroundColor = [UIColor colorWithRed:0.78 green:0.60 blue:0.23 alpha:1.0];
        self.versionChip.textColor = [UIColor whiteColor];
    }
    [self lui_refreshAvatar];
    [self lui_refreshStatus];
    [self setNeedsLayout];
}

/// 头像：当前微信账号头像（2026-09-21 用户：「顶部的 L 图像要改成显示用户的头像」）；取不到就露出石墨底「L」字标。
- (void)lui_refreshAvatar {
    UIImage *avatar = LUISettingsAvatarImage();
    self.avatarImageView.image = avatar;
    self.avatarImageView.hidden = avatar == nil;
    self.avatarGlyph.hidden = avatar != nil;
}

/// 状态胶囊 + 开关同步读配置：总开关开 → 砂金点「已启用」，关 → 三级灰点「未启用」。
- (void)lui_refreshStatus {
    BOOL enabled = self.key.length ? LUIConfigBool(self.key, NO) : NO;
    self.toggle.on = enabled;
    [self.toggleHost setNeedsLayout];   // 日夜皮肤按新 on 状态对齐（代码 setOn 不发 ValueChanged）
    self.statusLabel.text = enabled ? @"已启用" : @"未启用";
    self.statusLabel.textColor = enabled ? LUISettingsLiquidDynamicColor([UIColor colorWithRed:0.49 green:0.38 blue:0.20 alpha:1.0],
                                                                         [UIColor colorWithRed:0.85 green:0.75 blue:0.56 alpha:1.0])
                                         : LUISettingsInk2Color();
    self.statusDot.backgroundColor = enabled ? LUISettingsAccentColor() : LUISettingsInk3Color();
    self.statusChip.backgroundColor = enabled ? LUISettingsBadgeBackgroundColor() : LUISettingsControlTrackColor();
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat W = CGRectGetWidth(b);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.sheenLayer.frame = b;
    // 水纹圆心在右上出画处：设计稿 230 方框 right:-54 / top:-64 → 圆心 (W − 61, 51)，四圈半径 42 / 66 / 90 / 112。
    CGPoint c = CGPointMake(W - 61.0, 51.0);
    UIBezierPath *ripple = [UIBezierPath bezierPath];
    CGFloat radii[4] = {42.0, 66.0, 90.0, 112.0};
    for (int i = 0; i < 4; i++) {
        [ripple appendPath:[UIBezierPath bezierPathWithArcCenter:c radius:radii[i] startAngle:0 endAngle:2 * M_PI clockwise:YES]];
    }
    self.rippleLayer.path = ripple.CGPath;
    self.rippleLayer.frame = b;
    [CATransaction commit];

    CGFloat padX = 16.0, padTop = 14.0;
    self.avatarView.frame = CGRectMake(padX, padTop, 48.0, 48.0);
    // 右侧开关 44×26 垂直对齐头像中心。
    CGRect th = self.toggleHost.frame;
    th.origin = CGPointMake(W - padX - CGRectGetWidth(th), padTop + 24.0 - CGRectGetHeight(th) * 0.5);
    self.toggleHost.frame = th;
    CGFloat metaX = CGRectGetMaxX(self.avatarView.frame) + 13.0;
    CGFloat metaW = MAX(0.0, CGRectGetMinX(th) - 6.0 - metaX);
    CGFloat nameH = MAX(24.0, ceil(LUISettingsSafeLineHeight(self.nameLabel.font)));
    CGFloat chipH = 18.0;
    CGFloat blockH = nameH + 5.0 + chipH;
    CGFloat nameY = padTop + MAX(0.0, floor((48.0 - blockH) * 0.5));
    self.nameLabel.frame = CGRectMake(metaX, nameY, metaW, nameH);
    CGFloat chipY = CGRectGetMaxY(self.nameLabel.frame) + 5.0;
    CGFloat x = metaX;
    if (!self.versionChip.hidden) {
        CGFloat vw = MIN(metaW, ceil([self.versionChip sizeThatFits:CGSizeMake(metaW, chipH)].width) + 16.0);
        self.versionChip.frame = CGRectMake(x, chipY, vw, chipH);
        x += vw + 6.0;
    }
    CGFloat sw = ceil([self.statusLabel sizeThatFits:CGSizeMake(metaW, chipH)].width);
    CGFloat statusW = MIN(MAX(0.0, metaX + metaW - x), 8.0 + 6.0 + 5.0 + sw + 8.0);
    self.statusChip.frame = CGRectMake(x, chipY, statusW, chipH);
    self.statusDot.frame = CGRectMake(8.0, (chipH - 6.0) * 0.5, 6.0, 6.0);
    self.statusLabel.frame = CGRectMake(19.0, 0, MAX(0.0, statusW - 19.0 - 8.0), chipH);

    // 底部两枚按钮：28 高，紧挨着从左排，按标题自适应宽。
    CGFloat btnY = padTop + 48.0 + 12.0;
    CGFloat bx = padX;
    for (UIButton *btn in @[self.infoButton, self.logButton]) {
        CGFloat bw = ceil([btn sizeThatFits:CGSizeMake(200.0, 28.0)].width);
        btn.frame = CGRectMake(bx, btnY, bw, 28.0);
        UIView *glass = [btn viewWithTag:90210];
        if (glass) glass.frame = btn.bounds;
        bx += bw + 8.0;
    }
}

- (void)lui_toggleChanged:(UISwitch *)sender {
    if (!self.key.length) return;
    // 与 LUISettingsSwitchCell.changed: 同一口径：落盘 → 联动 → 整表重载 → 响应链通知。
    LUIConfigSetBool(self.key, sender.isOn);
    LUISettingsApplyChangedKey(self.key);
    [self lui_refreshStatus];
    UIView *cursor = self.superview;
    while (cursor && ![cursor isKindOfClass:UITableView.class]) cursor = cursor.superview;
    if ([cursor isKindOfClass:UITableView.class]) [(UITableView *)cursor reloadData];
    LUISettingsNotifyValueChangedFromResponder(self, self.key);
}
- (void)lui_infoTapped { if (self.onInfo) self.onInfo(); }
- (void)lui_logTapped { if (self.onChangelog) self.onChangelog(); }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.onInfo = nil;
    self.onChangelog = nil;
}
@end
