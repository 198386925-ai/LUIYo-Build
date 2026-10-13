#!/usr/bin/env python3
"""Robust hero fix: keyword-based replacement, no context matching."""
import re
import sys
from pathlib import Path

def fix(path):
    p = Path(path)
    if not p.exists():
        print(f"NOT FOUND: {path}")
        return False
    s = p.read_text(encoding='utf-8', errors='ignore')
    orig = s

    # 1. Name -> LUIYo (any line containing youyou.hero.name)
    s = re.sub(
        r'NSString\s*\*name\s*=\s*\[NSUserDefaults\.standardUserDefaults\s+stringForKey:@"youyou\.hero\.name"\][^;]*;',
        'NSString *name = @"LUIYo";',
        s
    )

    # 2. Version -> # ID device code (replace the Version/Build format line)
    # Find: NSString *version = [NSString stringWithFormat:@"Version...Build...", ...];
    if 'stringWithFormat:@"Version' in s:
        # Replace the three-line version block with device ID logic
        pattern = r'NSString\s*\*shortVer\s*=.*?;\s*\n\s*NSString\s*\*buildNum\s*=.*?;\s*\n\s*NSString\s*\*version\s*=\s*\[NSString\s+stringWithFormat:@"Version[^"]*"[^\]]*\];'
        replacement = (
            'NSString *tier = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.auth.tier"] ?: @"free";\n'
            '    BOOL isMember = ![tier isEqualToString:@"free"];\n'
            '    NSString *deviceCode = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.device.code"];\n'
            '    if (!deviceCode || deviceCode.length == 0) {\n'
            '        NSString *uuid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];\n'
            '        NSString *shortId = [[uuid stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:6];\n'
            '        deviceCode = [NSString stringWithFormat:@"D-%@", [shortId uppercaseString]];\n'
            '    }\n'
            '    NSString *version = [NSString stringWithFormat:@"# ID %@", deviceCode];'
        )
        s2 = re.sub(pattern, replacement, s, flags=re.DOTALL)
        if s2 != s:
            s = s2
            print("Version block replaced")
        else:
            print("Version pattern not matched, trying line-by-line")
            # Fallback: replace just the version line
            s = re.sub(
                r'NSString\s*\*version\s*=\s*\[NSString\s+stringWithFormat:@"Version[^"]*"[^\]]*\];',
                'NSString *version = [NSString stringWithFormat:@"# ID %@", deviceCode];',
                s
            )

    # 3. Add gradient styling after configureWithTitle (only if not already added)
    if 'badgeGradient' not in s:
        marker = '[cell configureWithTitle:name version:version key:@"luiyo.hero.enabled"];'
        if marker in s:
            style = marker + (
                '\n    { // LUIYo device badge styling'
                '\n    UIColor *bgS, *bgE, *txC;'
                '\n    if (isMember) { bgS=[UIColor colorWithRed:0.78 green:0.60 blue:0.23 alpha:1.0]; bgE=[UIColor colorWithRed:0.64 green:0.49 blue:0.16 alpha:1.0]; txC=[UIColor whiteColor]; }'
                '\n    else { bgS=[UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0]; bgE=[UIColor colorWithRed:0.85 green:0.85 blue:0.87 alpha:1.0]; txC=[UIColor colorWithRed:0.45 green:0.45 blue:0.48 alpha:1.0]; }'
                '\n    cell.versionChip.textColor = txC;'
                '\n    for (CALayer *ly in [cell.versionChip.layer.sublayers copy]) { if ([ly.name isEqualToString:@"badgeGradient"]) [ly removeFromSuperlayer]; }'
                '\n    CAGradientLayer *gl = [CAGradientLayer layer]; gl.name=@"badgeGradient";'
                '\n    gl.colors=@[(id)bgS.CGColor,(id)bgE.CGColor]; gl.cornerRadius=9;'
                '\n    [cell.versionChip.layer insertSublayer:gl atIndex:0];'
                '\n    dispatch_async(dispatch_get_main_queue(), ^{ gl.frame = cell.versionChip.bounds; });'
                '\n    }'
            )
            s = s.replace(marker, style, 1)
            print("Style block added")

    if s != orig:
        p.write_text(s, encoding='utf-8')
        print(f"FIXED: {path}")
        return True
    print(f"ERROR: NO CHANGE MADE TO {path} - patterns did not match!")
    # Print relevant lines for debugging
    for i, line in enumerate(orig.split('\n'), 1):
        if 'youyou.hero' in line or 'Version' in line and 'stringWithFormat' in line:
            print(f"  Line {i}: {line.strip()[:100]}")
    sys.exit(1)

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else 'YouYouLUI_iOS/YouYouLUI/LUISettingsHeroAdapter.m'
    fix(target)
