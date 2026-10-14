#!/usr/bin/env python3
"""Build-time: inject 1.0.6 changelog into Web/index.html"""
from pathlib import Path

CHANGELOG_106 = [
    "新增：支持图标上传、关键词批量导入、双分类补全与 ZIP 导出。",
    "优化：首页、规则与设置采用系统原生玻璃，低版本自动使用原生磨砂；缩小工具栏文字与规则条目间距。",
    "优化：原版微信与 LiquidUI 分类及导入入口互换，默认显示原版微信；统一反馈与客服联系入口图标。",
    "优化：移除分类描边、规则分割线及多余阴影；卡片颜色仅作用于授权上方的品牌卡，统一开关样式。",
    "修复：修复导入图片删除、补全导出、主题字体保存及底栏搜索布局切换。",
    "修复：优化底栏切换响应，恢复悬浮底栏与首页安全区，保持设置展开状态。",
    "修复：插件信息与更新日志支持定位展开，再次点击收起。",
]

def build_html_items():
    items = []
    for line in CHANGELOG_106:
        if line.startswith("新增："):
            cls, text = "add", line[3:]
        elif line.startswith("优化："):
            cls, text = "opt", line[3:]
        elif line.startswith("修复："):
            cls, text = "fix", line[3:]
        else:
            cls, text = "opt", line
        # Map to Chinese label
        label = {"add": "新增", "opt": "优化", "fix": "修复"}[cls]
        items.append(f'<p><b class="{cls}">{label}</b> {text}</p>')
    return "".join(items)

def main():
    files = list(Path(".").rglob("Web/index.html"))
    if not files:
        print("Web/index.html not found")
        return
    p = files[0]
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "Version 1.0.6" in s:
        print("1.0.6 already present")
        return
    orig = s
    items_html = build_html_items()
    # Format 1: inlineVersion (settings page)
    old1 = '<section class="inlineVersion"><div class="inlineVersionTitle">Version 1.0.7'
    new1 = f'<section class="inlineVersion"><div class="inlineVersionTitle">Version 1.0.6</div>{items_html}</section>\n{old1}'
    # Format 1: inlineVersion (settings page) - insert before 1.0.7
    import re
    # Find the 1.0.7 section and insert 1.0.6 before it
    pattern1 = r'(<section class="inlineVersion"><div class="inlineVersionTitle">Version 1\.0\.7)'
    replacement1 = f'<section class="inlineVersion"><div class="inlineVersionTitle">Version 1.0.6</div>{items_html}</section>\n\\1'
    s, n1 = re.subn(pattern1, replacement1, s, count=1)
    if n1 > 0: print("Patched inlineVersion")
    # Format 2: logCard (changelog page)
    pattern2 = r'(<article class="logCard"><div class="logTitle">Version 1\.0\.7)'
    replacement2 = f'<article class="logCard"><div class="logTitle">Version 1.0.6</div>{items_html}</article>\n\\1'
    s, n2 = re.subn(pattern2, replacement2, s, count=1)
    if n2 > 0: print("Patched logCard")
    if s != orig:
        p.write_text(s, encoding="utf-8")
        print(f"WROTE {p}")
    else:
        print("No changes")

if __name__ == "__main__":
    main()
