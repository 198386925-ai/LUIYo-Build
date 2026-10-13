#!/usr/bin/env python3
"""Apply LUIYo hero modifications directly (no patch file needed)."""
import re
import sys
from pathlib import Path

def patch_hero_adapter(path):
    s = Path(path).read_text(encoding='utf-8')
    orig = s
    
    # 1. Hardcode name to LUIYo
    s = re.sub(
        r'NSString \*name = \[NSUserDefaults\.standardUserDefaults stringForKey:@"youyou\.hero\.name"\] \?: @"[^"]*";',
        'NSString *name = @"LUIYo";',
        s
    )
    
    # 2. Replace version pill with device ID
    old_version = '    NSString *shortVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.6";\n    NSString *buildNum = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";\n    NSString *version = [NSString stringWithFormat:@"Version%@ Build%@", shortVer, buildNum];'
    
    new_version = '    NSString *tier = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.auth.tier"] ?: @"free";\n    BOOL isMember = ![tier isEqualToString:@"free"];\n    NSString *deviceCode = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.device.code"];\n    if (!deviceCode || deviceCode.length == 0) {\n        NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];\n        NSString *shortId = [[uuid stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:6];\n        deviceCode = [NSString stringWithFormat:@"D-%@", [shortId uppercaseString]];\n    }\n    NSString *version = [NSString stringWithFormat:@"# ID %@", deviceCode];'
    
    if old_version in s:
        s = s.replace(old_version, new_version, 1)
    
    # 3. Add gradient styling after configureWithTitle
    old_config = '    [cell configureWithTitle:name version:version key:@"luiyo.hero.enabled"];'
    new_config = old_config + '\n    UIColor *bgStart, *bgEnd, *textColor;\n    if (isMember) {\n        bgStart = [UIColor colorWithRed:0.78 green:0.60 blue:0.23 alpha:1.0];\n        bgEnd = [UIColor colorWithRed:0.64 green:0.49 blue:0.16 alpha:1.0];\n        textColor = [UIColor whiteColor];\n    } else {\n        bgStart = [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0];\n        bgEnd = [UIColor colorWithRed:0.85 green:0.85 blue:0.87 alpha:1.0];\n        textColor = [UIColor colorWithRed:0.45 green:0.45 blue:0.48 alpha:1.0];\n    }\n    cell.versionChip.textColor = textColor;\n    for (CALayer *layer in [cell.versionChip.layer.sublayers copy]) {\n        if ([layer.name isEqualToString:@"badgeGradient"]) [layer removeFromSuperlayer];\n    }\n    CAGradientLayer *gradient = [CAGradientLayer layer];\n    gradient.name = @"badgeGradient";\n    gradient.colors = @[(id)bgStart.CGColor, (id)bgEnd.CGColor];\n    gradient.cornerRadius = 9;\n    [cell.versionChip.layer insertSublayer:gradient atIndex:0];\n    dispatch_async(dispatch_get_main_queue(), ^{ gradient.frame = cell.versionChip.bounds; });'
    
    if old_config in s and 'badgeGradient' not in s:
        s = s.replace(old_config, new_config, 1)
    
    if s != orig:
        Path(path).write_text(s, encoding='utf-8')
        print(f"Patched {path}")
        return True
    else:
        print(f"No changes for {path}")
        return False

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'YouYouLUI_iOS/YouYouLUI/LUISettingsHeroAdapter.m'
    patch_hero_adapter(path)
