#!/usr/bin/env python3
"""Build-time fix: inject the missing Version 1.0.6 changelog section into
YouYouLUI_iOS/YouYouLUI/Web/index.html.

v2 changes (2026-10-14): FAILS LOUDLY instead of silently skipping.
The v1 script printed "skip ..." and exited 0 on every failure mode, so
run 38546079447 shipped without the 1.0.6 section and nobody noticed until
the user asked. This version exits non-zero with a clear INJECT-106 FAIL
banner whenever the injection cannot be completed, so a broken wiring
breaks the build instead of shipping a bad IPA.

Behavior:
- Target index.html must exist, else exit 2.
- For each known changelog container: insert the 1.0.6 block right after
  the 1.0.7 block. Skip only if 1.0.6 is already present (idempotent).
- If a container is absent, or the 1.0.7 anchor cannot be found, that is a
  hard failure (exit 2) -- the markup probably changed and a human must look.
- Fallback: if 1.0.7 anchor missing, insert before the 1.0.5 block.
- On success prints INJECT-106 OK lines (grep-able in CI logs) and the
  total inserted block count. Exit 0 only when every container is done.

Usage: python3 inject-106-changelog-v2.py [path-to-index.html]
"""
import re
import sys
from pathlib import Path

ENTRIES = [
    ("add", "支持图标上传、关键词批量导入、双分类补全与 ZIP 导出。"),
    ("opt", "首页、规则与设置采用系统原生玻璃，低版本自动使用原生磨砂；缩小工具栏文字与规则条目间距。"),
    ("opt", "原版微信与 LiquidUI 分类及导入入口互换，默认显示原版微信；统一反馈与客服联系入口图标。"),
    ("opt", "移除分类描边、规则分割线及多余阴影；卡片颜色仅作用于授权上方的品牌卡，统一开关样式。"),
    ("fix", "修复导入图片删除、补全导出、主题字体保存及底栏搜索布局切换。"),
    ("fix", "优化底栏切换响应，恢复悬浮底栏与首页安全区，保持设置展开状态。"),
    ("fix", "插件信息与更新日志支持定位展开，再次点击收起。"),
]
LABELS = {"add": "新增", "opt": "优化", "fix": "修复"}

# (name, container_open_marker, block_tag, block_class, title_class)
CONTAINERS = [
    ("settings-inline", '<div class="settingsFoldBody changelogInline">',
     "section", "inlineVersion", "inlineVersionTitle"),
    ("log-cards", '<div class="logCards">',
     "article", "logCard", "logTitle"),
]


def fail(msg):
    print("INJECT-106 FAIL: " + msg, file=sys.stderr)
    sys.exit(2)


def render_block(tag, cls, title_cls):
    paras = "".join(
        '<p><b class="%s">%s</b> %s</p>' % (kind, LABELS[kind], text)
        for kind, text in ENTRIES
    )
    return '<%s class="%s"><div class="%s">Version 1.0.6</div>%s</%s>' % (
        tag, cls, title_cls, paras, tag)


def insert_into_container(html, name, open_marker, tag, cls, title_cls):
    start = html.find(open_marker)
    if start < 0:
        fail("container %r (%s) not found in index.html" % (name, open_marker[:50]))
    # Bound the search to this container's neighbourhood (containers < 200KB).
    window = html[start:start + 200000]
    if "Version 1.0.6" in window:
        print("INJECT-106 OK: %s already has 1.0.6, skipped (idempotent)" % name)
        return html, 0
    # Primary anchor: insert right after the 1.0.7 block.
    anchor = re.search(r"Version 1\.0\.7", window)
    anchor_ver = "1.0.7"
    if not anchor:
        # Fallback anchor: insert right before the 1.0.5 block.
        m105 = re.search(r"Version 1\.0\.5", window)
        if not m105:
            fail("container %r: neither 1.0.7 nor 1.0.5 anchor found" % name)
        insert_at = start + m105.start()
        anchor_ver = "1.0.5(before)"
    else:
        close_tag = "</%s>" % tag
        close_idx = window.find(close_tag, anchor.end())
        if close_idx < 0:
            fail("container %r: 1.0.7 block has no closing <%s>" % (name, tag))
        insert_at = start + close_idx + len(close_tag)
    block = render_block(tag, cls, title_cls)
    html = html[:insert_at] + "\n" + block + html[insert_at:]
    print("INJECT-106 OK: inserted 1.0.6 into %s (anchor %s)" % (name, anchor_ver))
    return html, 1


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "YouYouLUI_iOS/YouYouLUI/Web/index.html")
    print("INJECT-106: target = %s" % path.resolve())
    if not path.is_file():
        fail("index.html not found at %s (cwd=%s)"
             % (path, Path.cwd()))
    html = path.read_text(encoding="utf-8")
    total = 0
    for name, marker, tag, cls, title_cls in CONTAINERS:
        html, n = insert_into_container(html, name, marker, tag, cls, title_cls)
        total += n
    path.write_text(html, encoding="utf-8")
    count = html.count("Version 1.0.6")
    if count < 2:
        fail("expected >=2 'Version 1.0.6' occurrences after injection, found %d" % count)
    print("INJECT-106 OK: wrote %s, inserted %d new block(s), total 1.0.6 occurrences=%d"
          % (path, total, count))


if __name__ == "__main__":
    main()
