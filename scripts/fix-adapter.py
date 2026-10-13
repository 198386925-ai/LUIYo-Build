#!/usr/bin/env python3
"""Fix LUISettingsHeroAdapter.m: LUIYo + tier device code (no crown)."""
import re
import sys
from pathlib import Path

def main():
    files = list(Path(".").rglob("LUISettingsHeroAdapter.m"))
    files = [f for f in files if "YouYouLUI_iOS" in str(f)]
    if not files:
        print("Adapter not found")
        sys.exit(0)
    p = files[0]
    s = p.read_text(encoding="utf-8", errors="ignore")
    orig = s

    # 1. Name -> LUIYo
    s = re.sub(
        r'NSString\s*\*name\s*=\s*[^;]*youyou\.hero\.name[^;]*;',
        'NSString *name = @"LUIYo";',
        s
    )
    s = s.replace('@"Liquid UI"', '@"LUIYo"')

    # 2. Find version assignment and replace with tier+device
    # Look for: NSString *version = [NSString stringWithFormat:@"Version...
    ver_match = re.search(
        r'(NSString\s*\*version\s*=\s*\[NSString\s+stringWithFormat:@")[^"]*(".*?\];)',
        s,
        re.DOTALL
    )
    if ver_match and '普通会员' not in s:
        old_ver = ver_match.group(0)
        new_ver = '''NSString *version = ({
        NSString *_t = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.auth.tier"] ?: @"free";
        NSString *_tn = @"免费用户";
        if ([_t isEqualToString:@"vip"]) _tn = @"普通会员";
        else if ([_t isEqualToString:@"svip"]) _tn = @"SVIP会员";
        NSString *_dc = [NSUserDefaults.standardUserDefaults stringForKey:@"youyou.device.code"];
        if (!_dc || _dc.length == 0) {
            NSString *_u = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
            NSString *_s = [[_u stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:6];
            _dc = [NSString stringWithFormat:@"D-%@", [_s uppercaseString]];
        }
        [NSString stringWithFormat:@"%@ · %@", _tn, _dc];
    });'''
        s = s.replace(old_ver, new_ver, 1)
        print("Adapter version replaced with tier+device")

    if s != orig:
        p.write_text(s, encoding="utf-8")
        print(f"WROTE {p}")
    else:
        print("No change to adapter")
    sys.exit(0)

if __name__ == "__main__":
    main()
