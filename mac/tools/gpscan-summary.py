#!/usr/bin/env python3
"""分析 GrandPerspective 匯出的 .gpscan 檔，印出目錄樹、最大檔案與已知 pattern 彙總。

.gpscan 是 gzip 壓縮的 XML（部分版本未壓縮）：
  <GrandPerspectiveScanDump>
    <ScanInfo volumePath volumeSize freeSpace scanTime fileSizeMeasure>
      <Folder name="">            ← 根目錄，name 是空字串
        <Folder name="Users"> ... <File name="x" size="123"/> ...

檔案可能解壓後近 1 GB、數百萬個 File，所以用 iterparse 串流解析並即時 clear()。
只用 Python 標準函式庫。

用法範例（在 repo 的 mac/ 目錄執行）：
  tools/gpscan-summary.py scan.gpscan --depth 2 --min-size 5G
  tools/gpscan-summary.py scan.gpscan --root ~/Library --depth 1 --min-size 500M
"""

import argparse
import gzip
import heapq
import os
import sys
import xml.etree.ElementTree as ET

GIB = 1024 ** 3

# 已知會長大的目錄名稱 → 彙總標籤。同一標籤只算最外層（巢狀的不重複計算）。
PATTERNS = {
    "node_modules": "node_modules",
    "build": "build",
    ".gradle": ".gradle",
    "DerivedData": "DerivedData",
    "Caches": "Caches",
    ".git": ".git",
    ".dart_tool": ".dart_tool",
    "Pods": "Pods",
    "__pycache__": "__pycache__",
    ".venv": ".venv/venv",
    "venv": ".venv/venv",
    ".next": ".next",
    ".pub-cache": ".pub-cache",
}
CODE_SIGN_CLONE_SUFFIX = ".code_sign_clone"


def pattern_label(name):
    if name.endswith(CODE_SIGN_CLONE_SUFFIX):
        return "code_sign_clone"
    return PATTERNS.get(name)


def parse_size(text):
    """'500M'、'1.5G'、'2T'、'1024' → bytes（二進位單位）。"""
    t = text.strip().upper()
    for suffix in ("IB", "B"):
        if t.endswith(suffix) and len(t) > len(suffix) and t[-len(suffix) - 1] in "KMGT":
            t = t[: -len(suffix)]
            break
    units = {"K": 1024, "M": 1024 ** 2, "G": 1024 ** 3, "T": 1024 ** 4}
    try:
        if t and t[-1] in units:
            return int(float(t[:-1]) * units[t[-1]])
        return int(float(t))
    except ValueError:
        raise argparse.ArgumentTypeError("無法解析大小：%r（例：500M、1.5G、2T）" % text)


def gib(n):
    return "%.2f" % (n / GIB)


def open_scan(path):
    with open(path, "rb") as fh:
        magic = fh.read(2)
    if magic == b"\x1f\x8b":
        return gzip.open(path, "rb")
    return open(path, "rb")


def display(path):
    return path or "/"


def under(path, root):
    """path 是否在 root 子樹內（含 root 本身）。root 為 '' 代表整個 volume。"""
    if not root:
        return True
    return path == root or path.startswith(root + "/")


def scan(file_path, root, top_n):
    info = {}
    sizes = {}                 # folder path → bytes（根為 ''）
    children = {}              # folder path → [child folder path]
    top_files = []             # min-heap of (size, path)
    pattern_hits = []          # (label, path, size)

    path_stack = []            # 目前所在 folder 的完整路徑
    size_stack = []            # 對應 folder 的累計大小
    label_stack = []           # 對應 folder 的 pattern 標籤（或 None）
    open_labels = {}           # 祖先中各標籤的出現次數，用來判斷「最外層」

    with open_scan(file_path) as fh:
        for ev, el in ET.iterparse(fh, events=("start", "end")):
            tag = el.tag
            if ev == "start":
                if tag == "Folder":
                    name = el.get("name", "")
                    if not path_stack:
                        path = ""             # 根目錄一律正規化成 ''
                    else:
                        path = path_stack[-1] + "/" + name
                    if path_stack:
                        children.setdefault(path_stack[-1], []).append(path)
                    path_stack.append(path)
                    size_stack.append(0)
                    label = pattern_label(name) if path_stack[:-1] else None
                    if label and open_labels.get(label, 0) == 0:
                        label_stack.append(label)
                    else:
                        label_stack.append(None)
                    if label:
                        open_labels[label] = open_labels.get(label, 0) + 1
                elif tag == "ScanInfo":
                    info = dict(el.attrib)
                continue

            # ev == "end"
            if tag == "File":
                size = int(el.get("size", 0) or 0)
                if size_stack:
                    size_stack[-1] += size
                    if top_n > 0:
                        parent = path_stack[-1]
                        if under(parent, root):
                            fpath = parent + "/" + el.get("name", "")
                            if len(top_files) < top_n:
                                heapq.heappush(top_files, (size, fpath))
                            elif size > top_files[0][0]:
                                heapq.heapreplace(top_files, (size, fpath))
            elif tag == "Folder":
                size = size_stack.pop()
                path = path_stack.pop()
                outer_label = label_stack.pop()
                sizes[path] = size
                if size_stack:
                    size_stack[-1] += size
                name = path.rsplit("/", 1)[-1] if path else ""
                label = pattern_label(name) if path else None
                if label:
                    open_labels[label] -= 1
                if outer_label and under(path, root):
                    pattern_hits.append((outer_label, path, size))
            el.clear()

    return info, sizes, children, sorted(top_files, reverse=True), pattern_hits


def print_tree(sizes, children, root, depth, min_size):
    lines = []

    def walk(path, level):
        lines.append("%s%8s  %s" % ("  " * level, gib(sizes.get(path, 0)), display(path)))
        if level >= depth:
            return
        kids = [c for c in children.get(path, []) if c != path]   # 防呆：不把自己列成子項
        kids.sort(key=lambda c: sizes.get(c, 0), reverse=True)
        for c in kids:
            if sizes.get(c, 0) >= min_size:
                walk(c, level + 1)

    walk(root, 0)
    return lines


def main():
    ap = argparse.ArgumentParser(
        description="分析 GrandPerspective 的 .gpscan 匯出檔（單位：GiB）")
    ap.add_argument("file", metavar="FILE", help=".gpscan 檔案路徑")
    ap.add_argument("--depth", type=int, default=3, help="樹狀展開深度（預設 3）")
    ap.add_argument("--min-size", type=parse_size, default=parse_size("1G"),
                    help="只列出至少這麼大的目錄，例：500M、1.5G（預設 1G）")
    ap.add_argument("--root", default="/",
                    help="從這個子樹開始展開，例：/Users 或 ~/Library（預設 /）")
    ap.add_argument("--top-files", type=int, default=20, help="列出最大的 N 個檔案（預設 20）")
    args = ap.parse_args()

    root = os.path.expanduser(args.root).rstrip("/")   # '/' → ''

    try:
        info, sizes, children, top_files, hits = scan(args.file, root, args.top_files)
    except (OSError, ET.ParseError, EOFError) as e:
        print("讀取失敗：%s" % e, file=sys.stderr)
        return 1

    if root not in sizes:
        print("scan 裡找不到 --root 指定的路徑：%s" % display(root), file=sys.stderr)
        return 1

    print("單位：GiB（1 GiB = 1024^3 bytes）")
    print()
    print("== ScanInfo ==")
    vol = int(info.get("volumeSize", 0) or 0)
    free = int(info.get("freeSpace", 0) or 0)
    total = sizes.get("", 0)
    print("volume        %s  (%s)" % (info.get("volumePath", "?"), info.get("scanTime", "?")))
    print("volume 大小   %8s" % gib(vol))
    print("剩餘空間      %8s" % gib(free))
    print("已用空間      %8s" % gib(vol - free))
    print("掃到的總量    %8s  (fileSizeMeasure=%s)" % (gib(total), info.get("fileSizeMeasure", "?")))
    print("差距          %8s  ← 差距通常是 APFS 快照／系統 volume 等掃不到的部分" % gib(vol - free - total))
    print()

    print("== 目錄樹（%s，depth %d，>= %s GiB） ==" % (display(root), args.depth, gib(args.min_size)))
    for line in print_tree(sizes, children, root, args.depth, args.min_size):
        print(line)
    print()

    if args.top_files > 0:
        print("== 最大的 %d 個檔案（%s 底下） ==" % (args.top_files, display(root)))
        for size, path in top_files:
            print("%8s  %s" % (gib(size), path))
        print()

    print("== 已知 pattern 彙總（%s 底下；同名只算最外層） ==" % display(root))
    agg = {}
    for label, path, size in hits:
        s, n, big = agg.get(label, (0, 0, None))
        if big is None or size > big[1]:
            big = (path, size)
        agg[label] = (s + size, n + 1, big)
    if not agg:
        print("（無）")
    for label, (s, n, big) in sorted(agg.items(), key=lambda kv: kv[1][0], reverse=True):
        print("%8s  %-16s %6d 處   最大：%s (%s)" % (gib(s), label, n, big[0], gib(big[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
