#!/usr/bin/env python3
"""Directly fix LUISettingsHeroCell.m: hardcode LUIYo, show tier+device in version pill."""
import sys
from pathlib import Path

def main():
    files = list(Path(".").rglob("LUISettingsHeroCell.m"))
    files = [f for f in files if "YouYouLUI_iOS" in str(f)]
    if not files:
        print("Cell file not found")
        return
    p = files[0]
    s = p.read_text(encoding="utf-8", errors="ignore")
    orig = s

    # Replace the three lines in configureWithTitle
    old_block = '''    self.nameLabel.text = title ?: @"";
    self.versionChip.text = version.length ? version : @"";
    self.versionChip.hidden = version.length == 0;'''

    new_block = '''    self.nameLabel.text = @"LUIYo";
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
    if ([_tier isEqualToString:@"free"]) {
        self.versionChip.backgroundColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.94 alpha:1.0];
        self.versionChip.textColor = [UIColor colorWithRed:0.45 green:0.45 blue:0.48 alpha:1.0];
    } else {
        self.versionChip.backgroundColor = [UIColor colorWithRed:0.78 green:0.60 blue:0.23 alpha:1.0];
        self.versionChip.textColor = [UIColor whiteColor];
    }'''

    if old_block in s:
        s = s.replace(old_block, new_block, 1)
        print("Cell fixed: LUIYo + tier device code")
    else:
        print("Pattern not found in cell file")

    if s != orig:
        p.write_text(s, encoding="utf-8")
        print(f"WROTE {p}")

if __name__ == "__main__":
    main()
