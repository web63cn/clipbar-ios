#!/usr/bin/env python3
"""校验 project.pbxproj 的引用完整性（不依赖 Xcode）"""
import re
import sys

PATH = "ClipBar.xcodeproj/project.pbxproj"
s = open(PATH, encoding="utf-8").read()
problems = []


def section(name):
    m = re.search(r'/\* Begin ' + name + r' section \*/(.*?)/\* End ' + name + r' section \*/', s, re.S)
    return m.group(1) if m else ''


# 收集所有被定义的对象 ID
defined = set(re.findall(r'^\t\t([0-9A-F]{24}) /\*', s, re.M))
defined |= set(re.findall(r'^\t\t([0-9A-F]{24}) = \{', s, re.M))
defined |= set(re.findall(r'^\t\t([0-9A-F]{24}) /\*.*?\*/ = \{', s, re.M))

# BuildFile 段
bf = section('PBXBuildFile')
# buildFile 段里出现的所有 ID（定义处）
bf_ids = {}
for m in re.finditer(r'([0-9A-F]{24}) /\* (.+?) in ([^ ]+) \*/', bf):
    bf_ids[m.group(1)] = (m.group(2), m.group(3))

# FileReference 段
fr = section('PBXFileReference')
file_ids = set(re.findall(r'([0-9A-F]{24}) /\*', fr))

# 1. buildFile → fileRef（扫整段，appex 的格式不同所以不靠单条正则）
for m in re.finditer(r'fileRef = ([0-9A-F]{24});', bf):
    if m.group(1) not in file_ids:
        problems.append(f"fileRef 悬空: {m.group(1)}")

# 2. phase → buildFile
# 只在 phase 段里找引用（定义处不算）
phase_text = section('PBXSourcesBuildPhase') + section('PBXResourcesBuildPhase') \
    + section('PBXCopyFilesBuildPhase')
for bid, name in re.findall(r'([0-9A-F]{24}) /\* (.+?) in (?:Sources|Resources|Embed Foundation Extensions) \*/', phase_text):
    if bid not in bf_ids:
        problems.append(f"phase 引用悬空: {name}")

# 3. group children
g = section('PBXGroup')
for lst in re.findall(r'children = \((.*?)\);', g, re.S):
    for bid in re.findall(r'([0-9A-F]{24})', lst):
        if bid not in defined:
            problems.append(f"group children 悬空: {bid}")

# 4. 其它顶层引用
for pattern, label in [
    (r'buildConfigurationList = ([0-9A-F]{24})', 'buildConfigurationList'),
    (r'productRefGroup = ([0-9A-F]{24})', 'productRefGroup'),
    (r'mainGroup = ([0-9A-F]{24})', 'mainGroup'),
    (r'rootObject = ([0-9A-F]{24})', 'rootObject'),
    (r'target = ([0-9A-F]{24})', 'target'),
    (r'productReference = ([0-9A-F]{24})', 'productReference'),
    (r'containerPortal = ([0-9A-F]{24})', 'containerPortal'),
    (r'buildConfigurationList = ([0-9A-F]{24})', 'buildConfigurationList'),
]:
    for bid in re.findall(pattern, s):
        if bid not in defined:
            problems.append(f"{label} 悬空: {bid}")

# 5. XCConfigurationList 里的 buildConfigurations
for lst in re.findall(r'buildConfigurations = \((.*?)\);', s, re.S):
    for bid in re.findall(r'([0-9A-F]{24})', lst):
        if bid not in defined:
            problems.append(f"buildConfigurations 悬空: {bid}")

# 6. 编译次数检查
from collections import Counter
c = Counter(name for name, _ in bf_ids.values())
for name, cnt in c.items():
    # 共享源码两个 target 各编译一次；两个 target 也各有一份 Assets
    expect = 2 if name in ('AES.swift', 'ClipItem.swift',
                           'SharedStore.swift', 'Assets.xcassets') else 1
    if cnt != expect:
        problems.append(f"{name} 编译 {cnt} 次（期望 {expect}）")

# 7. 关键 target 存在
for t in ['ClipBar', 'ClipBarKeyboard']:
    if f'/* {t} */ = {{' not in s:
        problems.append(f"缺少 target: {t}")

# 8. 关键：每个 fileRef 的 path 必须真实存在
#    （fileRef 的 path 决定磁盘位置；
#      写错 → Xcode 报 "Build input files cannot be found"）
import os
fr_sec = section('PBXFileReference')
for m in re.finditer(r'([0-9A-F]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference;(.*?)\};', fr_sec, re.S):
    fid, fname, body = m.groups()
    pm = re.search(r'path = "([^"]+)"', body)
    if not pm:
        continue
    disk = pm.group(1)
    if not os.path.exists(disk):
        problems.append(f"fileRef 路径错误: {fname} → 磁盘上找不到 {disk}")

print(f"对象总数 {len(defined)}  BuildFile {len(bf_ids)}  FileReference {len(file_ids)}")
if problems:
    print("\n❌ 发现问题:")
    for p in sorted(set(problems)):
        print("   ", p)
    sys.exit(1)
else:
    print("\n✅ 工程引用完整性检查全部通过")
