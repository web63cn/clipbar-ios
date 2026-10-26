#!/usr/bin/env python3
"""
生成 ClipBar.xcodeproj/project.pbxproj

手写 pbxproj 容易出错（UUID 引用错一个就整个工程打不开），
所以用脚本生成 —— 改文件名、加文件只要重跑一次。

用法：python3 gen_xcodeproj.py
"""
import os
import hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(ROOT, "ClipBar.xcodeproj")


def uid(*parts):
    """稳定的 24 位十六进制 ID（同一路径永远生成同一个）"""
    h = hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()
    return h


# ---------------------------------------------------------------- 文件清单
APP_SOURCES = [
    "ClipBar/ClipBarApp.swift",
    "ClipBar/Core/ClipStore.swift",
    "ClipBar/Core/CloudSync.swift",
    "ClipBar/Views/HistoryView.swift",
    "ClipBar/Views/TextToolsView.swift",
    "ClipBar/Views/SettingsView.swift",
]

SHARED_SOURCES = [
    "Shared/AES.swift",
    "Shared/ClipItem.swift",
    "Shared/SharedStore.swift",
]

KB_SOURCES = [
    "ClipBarKeyboard/KeyboardController.swift",
]

APP_RESOURCES = [
    "ClipBar/Assets.xcassets",
]

KB_RESOURCES = [
    "ClipBarKeyboard/Assets.xcassets",
]

# ---------------------------------------------------------------- ID 生成
def build_ids():
    ids = {}
    for path in APP_SOURCES + SHARED_SOURCES + KB_SOURCES:
        ids[f"file:{path}"] = uid("file", path)
    for path in APP_RESOURCES + KB_RESOURCES:
        ids[f"file:{path}"] = uid("file", path)
    for path in ["ClipBar/Info.plist", "ClipBarKeyboard/Info.plist",
                 "ClipBar/ClipBar.entitlements", "ClipBarKeyboard/ClipBarKeyboard.entitlements"]:
        ids[f"file:{path}"] = uid("file", path)

    ids["appTarget"] = uid("target", "app")
    ids["kbTarget"] = uid("target", "kb")
    ids["appProduct"] = uid("product", "app")
    ids["kbProduct"] = uid("product", "kb")
    ids["appConfigList"] = uid("configlist", "app")
    ids["kbConfigList"] = uid("configlist", "kb")
    ids["projConfigList"] = uid("configlist", "proj")
    ids["appGroup"] = uid("group", "app")
    ids["kbGroup"] = uid("group", "kb")
    ids["sharedGroup"] = uid("group", "shared")
    ids["productsGroup"] = uid("group", "products")
    ids["mainGroup"] = uid("group", "main")
    ids["appProj"] = uid("project", "app")
    for name in ["Debug", "Release"]:
        ids[f"app:{name}"] = uid("buildconfig", "app", name)
        ids[f"kb:{name}"] = uid("buildconfig", "kb", name)
        ids[f"proj:{name}"] = uid("buildconfig", "proj", name)
    return ids


IDS = build_ids()

PBX_FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
}


def file_type(path):
    ext = os.path.splitext(path)[1]
    return PBX_FILE_TYPES.get(ext, "text")


def file_ref_block(ids):
    """fileRef 的 path 用**完整相对路径**。

    为什么要完整路径而不是文件名 + group 层级：
    - 层级 group（ClipBar → Core → ClipStore.swift）要写更多嵌套结构，容易错
    - 扁平写法：path = "ClipBar/Core/ClipStore.swift"，磁盘位置唯一确定

    group 只负责在 Xcode 里显示分类，不影响文件位置。
    """
    lines = []
    for path in APP_SOURCES + SHARED_SOURCES + KB_SOURCES + APP_RESOURCES + KB_RESOURCES:
        name = os.path.basename(path)
        lines.append(f'\t\t{ids["file:" + path]} /* {name} */ = {{isa = PBXFileReference; '
                     f'lastKnownFileType = {file_type(path)}; path = "{path}"; sourceTree = "<group>"; }};')
    for path in ["ClipBar/Info.plist", "ClipBarKeyboard/Info.plist",
                 "ClipBar/ClipBar.entitlements", "ClipBarKeyboard/ClipBarKeyboard.entitlements"]:
        name = os.path.basename(path)
        lines.append(f'\t\t{ids["file:" + path]} /* {name} */ = {{isa = PBXFileReference; '
                     f'lastKnownFileType = {file_type(path)}; path = "{path}"; sourceTree = "<group>"; }};')
    return "\n".join(lines)


def build_file_refs(ids):
    """生成 PBXFileReference 段落"""
    return (file_ref_block(ids) + "\n"
            + f'\t\t{ids["appProduct"]} /* ClipBar.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ClipBar.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
            + f'\t\t{ids["kbProduct"]} /* ClipBarKeyboard.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ClipBarKeyboard.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
            )


def build_file_types(ids):
    out = []
    for path in APP_SOURCES + SHARED_SOURCES + KB_SOURCES:
        out.append(f'\t\t{uid("filetype", path)} = {{isa = PBXFileType; explicitFileType = sourcecode.swift; '
                   f'includeInIndex = 0; name = "{os.path.basename(path)}"; path = "{os.path.basename(path)}"; '
                   f'sourceTree = "<group>"; fileEncoding = 4; lastKnownFileType = sourcecode.swift; }};')
    return "\n".join(out)


def build_build_files(ids):
    """PBXBuildFile：编译/资源引用"""
    out = []
    def bf(scope, path, phase):
        return (f'\t\t{uid("bf", scope, path)} /* {os.path.basename(path)} in {phase} */ = '
                f'{{isa = PBXBuildFile; fileRef = {ids["file:" + path]}; }};')

    for path in APP_SOURCES:
        out.append(bf("app", path, "Sources"))
    for path in SHARED_SOURCES:
        out.append(bf("app", path, "Sources"))
    for path in APP_RESOURCES:
        out.append(bf("app", path, "Resources"))
    for path in KB_SOURCES:
        out.append(bf("kb", path, "Sources"))
    for path in SHARED_SOURCES:
        out.append(bf("kb", path, "Sources"))
    for path in KB_RESOURCES:
        out.append(bf("kb", path, "Resources"))
    # appex 嵌入主 app
    out.append(f'\t\t{uid("bf", "appex")} /* ClipBarKeyboard.appex in Embed Foundation Extensions */ = '
               f'{{isa = PBXBuildFile; fileRef = {ids["kbProduct"]}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')
    return "\n".join(out)


def build_groups(ids):
    out = []

    # 主 group
    out.append(f'\t\t{ids["mainGroup"]} = {{')
    out.append('\t\t\tisa = PBXGroup;')
    out.append('\t\t\tchildren = (')
    out.append(f'\t\t\t\t{ids["appGroup"]} /* ClipBar */,')
    out.append(f'\t\t\t\t{ids["kbGroup"]} /* ClipBarKeyboard */,')
    out.append(f'\t\t\t\t{ids["sharedGroup"]} /* Shared */,')
    out.append(f'\t\t\t\t{ids["productsGroup"]} /* Products */,')
    out.append('\t\t\t);')
    out.append('\t\t\tname = ClipBar;')
    out.append('\t\t\tsourceTree = "<group>";')
    out.append('\t\t};')

    # App group
    out.append(f'\t\t{ids["appGroup"]} /* ClipBar */ = {{')
    out.append('\t\t\tisa = PBXGroup;')
    out.append('\t\t\tchildren = (')
    for path in APP_SOURCES:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    for path in APP_RESOURCES:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    for path in ["ClipBar/Info.plist", "ClipBar/ClipBar.entitlements"]:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    out.append('\t\t\t);')
    out.append('\t\t\tsourceTree = "<group>";')
    out.append('\t\t};')

    # Keyboard group
    out.append(f'\t\t{ids["kbGroup"]} /* ClipBarKeyboard */ = {{')
    out.append('\t\t\tisa = PBXGroup;')
    out.append('\t\t\tchildren = (')
    for path in KB_SOURCES + KB_RESOURCES:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    for path in ["ClipBarKeyboard/Info.plist", "ClipBarKeyboard/ClipBarKeyboard.entitlements"]:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    out.append('\t\t\t);')
    out.append('\t\t\tsourceTree = "<group>";')
    out.append('\t\t};')

    # Shared group（两个 target 共用的源码）
    out.append(f'\t\t{ids["sharedGroup"]} /* Shared */ = {{')
    out.append('\t\t\tisa = PBXGroup;')
    out.append('\t\t\tchildren = (')
    for path in SHARED_SOURCES:
        out.append(f'\t\t\t\t{ids["file:" + path]} /* {os.path.basename(path)} */,')
    out.append('\t\t\t);')
    out.append('\t\t\tsourceTree = "<group>";')
    out.append('\t\t};')

    # Products
    out.append(f'\t\t{ids["productsGroup"]} /* Products */ = {{')
    out.append('\t\t\tisa = PBXGroup;')
    out.append('\t\t\tchildren = (')
    out.append(f'\t\t\t\t{ids["appProduct"]} /* ClipBar.app */,')
    out.append(f'\t\t\t\t{ids["kbProduct"]} /* ClipBarKeyboard.appex */,')
    out.append('\t\t\t);')
    out.append('\t\t\tname = Products;')
    out.append('\t\t\tsourceTree = "<group>";')
    out.append('\t\t};')

    return "\n".join(out)


def build_sources_phase(ids, sources, name):
    out = [f'\t\t{uid("phase", name)} /* Sources */ = {{', '\t\t\tisa = PBXSourcesBuildPhase;',
           '\t\t\tbuildActionMask = 2147483647;', '\t\t\tfiles = (']
    for path in sources:
        out.append(f'\t\t\t\t{uid("bf", name, path)} /* {os.path.basename(path)} in Sources */,')
    out.append('\t\t\t);')
    out.append('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    out.append('\t\t};')
    return "\n".join(out)


def build_resources_phase(ids, resources, name):
    out = [f'\t\t{uid("phase_r", name)} /* Resources */ = {{', '\t\t\tisa = PBXResourcesBuildPhase;',
           '\t\t\tbuildActionMask = 2147483647;', '\t\t\tfiles = (']
    for path in resources:
        out.append(f'\t\t\t\t{uid("bf", name, path)} /* {os.path.basename(path)} in Resources */,')
    out.append('\t\t\t);')
    out.append('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
    out.append('\t\t};')
    return "\n".join(out)


def build_frameworks_phase(ids, name):
    return (f'\t\t{uid("phase_f", name)} /* Frameworks */ = {{\n'
            '\t\t\tisa = PBXFrameworksBuildPhase;\n'
            '\t\t\tbuildActionMask = 2147483647;\n'
            '\t\t\tfiles = (\n'
            '\t\t\t);\n'
            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            '\t\t};')


def build_embed_phase(ids):
    return (f'\t\t{uid("phase_e")} /* Embed Foundation Extensions */ = {{\n'
            '\t\t\tisa = PBXCopyFilesBuildPhase;\n'
            '\t\t\tbuildActionMask = 2147483647;\n'
            '\t\t\tdstPath = "";\n'
            '\t\t\tdstSubfolderSpec = 13;\n'
            '\t\t\tfiles = (\n'
            f'\t\t\t\t{uid("bf", "appex")} /* ClipBarKeyboard.appex in Embed Foundation Extensions */,\n'
            '\t\t\t);\n'
            '\t\t\tname = "Embed Foundation Extensions";\n'
            '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            '\t\t};')


def build_phases(ids):
    out = []
    out.append(build_sources_phase(ids, APP_SOURCES + SHARED_SOURCES, "app"))
    out.append(build_sources_phase(ids, KB_SOURCES + SHARED_SOURCES, "kb"))


    out.append(build_resources_phase(ids, APP_RESOURCES, "app"))
    out.append(build_resources_phase(ids, KB_RESOURCES, "kb"))


    out.append(build_frameworks_phase(ids, "app"))
    out.append(build_frameworks_phase(ids, "kb"))


    out.append(build_embed_phase(ids))

    return "\n".join(out)


def build_target(ids, name, target_id, product_id, product_name, product_type,
                 config_list, sources, resources, phase_prefix, dep_list=None, embed=None):
    out = [f'\t\t{target_id} /* {name} */ = {{', '\t\t\tisa = PBXNativeTarget;']
    out.append(f'\t\t\tbuildConfigurationList = {config_list} /* Build configuration list for PBXNativeTarget "{name}" */;')
    out.append('\t\t\tbuildPhases = (')
    out.append(f'\t\t\t\t{uid("phase", phase_prefix)} /* Sources */,')
    out.append(f'\t\t\t\t{uid("phase_f", phase_prefix)} /* Frameworks */,')
    out.append(f'\t\t\t\t{uid("phase_r", phase_prefix)} /* Resources */,')
    if embed:
        out.append(f'\t\t\t\t{uid("phase_e")} /* Embed Foundation Extensions */,')
    out.append('\t\t\t);')
    out.append('\t\t\tbuildRules = (')
    out.append('\t\t\t);')
    out.append('\t\t\tdependencies = (')
    if dep_list:
        out.append(f'\t\t\t\t{dep_list} /* PBXTargetDependency */,')
    out.append('\t\t\t);')
    out.append(f'\t\t\tname = {name};')
    out.append(f'\t\t\tproductName = {name};')
    out.append(f'\t\t\tproductReference = {product_id} /* {product_name} */;')
    out.append(f'\t\t\tproductType = "{product_type}";')
    out.append('\t\t};')
    return "\n".join(out)


def build_targets(ids):
    dep = uid("dep", "kb")
    out = []
    out.append(build_target(ids, "ClipBar", ids["appTarget"], ids["appProduct"],
                            "ClipBar.app", "com.apple.product-type.application",
                            ids["appConfigList"], APP_SOURCES + SHARED_SOURCES,
                            APP_RESOURCES, "app", dep, embed=True))
    out.append(build_target(ids, "ClipBarKeyboard", ids["kbTarget"], ids["kbProduct"],
                            "ClipBarKeyboard.appex", "com.apple.product-type.app-extension",
                            ids["kbConfigList"], KB_SOURCES + SHARED_SOURCES,
                            KB_RESOURCES, "kb"))

    out.append("/* Begin PBXTargetDependency section */")
    out.append(f'\t\t{dep} /* PBXTargetDependency */ = {{')
    out.append('\t\t\tisa = PBXTargetDependency;')
    out.append(f'\t\t\ttarget = {ids["kbTarget"]} /* ClipBarKeyboard */;')
    out.append(f'\t\t\ttargetProxy = {uid("proxy", "kb")} /* PBXContainerItemProxy */;')
    out.append('\t\t};')
    out.append("/* End PBXTargetDependency section */")
    out.append("/* Begin PBXContainerItemProxy section */")
    out.append(f'\t\t{uid("proxy", "kb")} /* PBXContainerItemProxy */ = {{')
    out.append('\t\t\tisa = PBXContainerItemProxy;')
    out.append(f'\t\t\tcontainerPortal = {ids["appProj"]} /* Project object */;')
    out.append('\t\t\tproxyType = 1;')
    out.append(f'\t\t\tremoteGlobalIDString = {ids["kbTarget"]};')
    out.append(f'\t\t\tremoteInfo = ClipBarKeyboard;')
    out.append('\t\t};')
    out.append("/* End PBXContainerItemProxy section */")
    return "\n".join(out)


BUILD_COMMON = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""


def build_config_list(ids, key, label, debug_settings, release_settings, base_name):
    out = [f'\t\t{ids[key + ":Debug"]} /* Debug */ = {{', '\t\t\tisa = XCBuildConfiguration;',
           '\t\t\tbuildSettings = {']
    out.append(BUILD_COMMON)
    out.append(debug_settings)
    out.append('\t\t\t};')
    out.append(f'\t\t\tname = Debug;')
    out.append(f'\t\t}};')
    out.append(f'\t\t{ids[key + ":Release"]} /* Release */ = {{')
    out.append('\t\t\tisa = XCBuildConfiguration;')
    out.append('\t\t\tbuildSettings = {')
    out.append(BUILD_COMMON)
    out.append(release_settings)
    out.append('\t\t\t};')
    out.append(f'\t\t\tname = Release;')
    out.append(f'\t\t}};')
    list_id = ids[key + "ConfigList"] if key + "ConfigList" in ids else ids[key + "ConfigList"]
    out.append(f'\t\t{list_id} /* Build configuration list for {label} */ = {{')
    out.append('\t\t\tisa = XCConfigurationList;')
    out.append('\t\t\tbuildConfigurations = (')
    out.append(f'\t\t\t\t{ids[key + ":Debug"]} /* Debug */,')
    out.append(f'\t\t\t\t{ids[key + ":Release"]} /* Release */,')
    out.append('\t\t\t);')
    out.append('\t\t\tdefaultConfigurationIsVisible = 0;')
    out.append('\t\t\tdefaultConfigurationName = Release;')
    out.append('\t\t};')
    return "\n".join(out)


def build_configs(ids):
    out = []

    # App target
    out.append(build_config_list(
        ids, "app", f'PBXNativeTarget "ClipBar"',
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = ClipBar/Info.plist;\n"
        "\t\t\t\tMARKETING_VERSION = 1.4;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.clipbar.ios;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = ClipBar/ClipBar.entitlements;\n",
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = ClipBar/Info.plist;\n"
        "\t\t\t\tMARKETING_VERSION = 1.4;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.clipbar.ios;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = ClipBar/ClipBar.entitlements;\n",
        "app"))

    # Keyboard target
    out.append(build_config_list(
        ids, "kb", f'PBXNativeTarget "ClipBarKeyboard"',
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = ClipBarKeyboard/Info.plist;\n"
        "\t\t\t\tMARKETING_VERSION = 1.4;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.clipbar.ios.keyboard;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = ClipBarKeyboard/ClipBarKeyboard.entitlements;\n",
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = ClipBarKeyboard/Info.plist;\n"
        "\t\t\t\tMARKETING_VERSION = 1.4;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.clipbar.ios.keyboard;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = ClipBarKeyboard/ClipBarKeyboard.entitlements;\n",
        "kb"))

    # Project level
    proj_debug = ("\t\t\t\tCODE_SIGN_IDENTITY = \"\";\n"
                  "\t\t\t\tCODE_SIGNING_REQUIRED = NO;\n"
                  "\t\t\t\tCODE_SIGNING_ALLOWED = NO;\n"
                  "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n"
                  "\t\t\t\tENABLE_TESTABILITY = YES;\n"
                  "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n"
                  "\t\t\t\tONLY_ACTIVE_ARCH = YES;\n"
                  "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
                  "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n")
    proj_release = ("\t\t\t\tCODE_SIGN_IDENTITY = \"\";\n"
                    "\t\t\t\tCODE_SIGNING_REQUIRED = NO;\n"
                    "\t\t\t\tCODE_SIGNING_ALLOWED = NO;\n"
                    "\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n"
                    "\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n"
                    "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
                    "\t\t\t\tVALIDATE_PRODUCT = YES;\n")
    out.append(build_config_list(ids, "proj", 'PBXProject "ClipBar"',
                                  proj_debug, proj_release, "proj"))
    return "\n".join(out)


def build_project(ids):
    out = ["// !$*UTF8*$!", "{",
           "\tarchiveVersion = 1;",
           "\tclasses = {",
           "\t};",
           "\tobjectVersion = 56;",
           "\tobjects = {",
           "",
           "/* Begin PBXBuildFile section */"]
    out.append(build_build_files(ids))
    out.append("/* End PBXBuildFile section */")
    out.append("")
    out.append("/* Begin PBXFileReference section */")
    out.append(build_file_refs(ids))
    out.append("/* End PBXFileReference section */")
    out.append("")
    out.append("")
    out.append("")
    out.append("")
    out.append("")
    out.append("/* Begin PBXGroup section */")
    out.append(build_groups(ids))
    out.append("/* End PBXGroup section */")
    out.append("")
    out.append("/* Begin PBXNativeTarget section */")
    out.append(build_targets(ids))
    out.append("/* End PBXNativeTarget section */")
    out.append("")
    out.append("/* Begin PBXSourcesBuildPhase section */")
    out.append(build_sources_phase(ids, APP_SOURCES + SHARED_SOURCES, "app"))
    out.append(build_sources_phase(ids, KB_SOURCES + SHARED_SOURCES, "kb"))
    out.append("/* End PBXSourcesBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXResourcesBuildPhase section */")
    out.append(build_resources_phase(ids, APP_RESOURCES, "app"))
    out.append(build_resources_phase(ids, KB_RESOURCES, "kb"))
    out.append("/* End PBXResourcesBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXFrameworksBuildPhase section */")
    out.append(build_frameworks_phase(ids, "app"))
    out.append(build_frameworks_phase(ids, "kb"))
    out.append("/* End PBXFrameworksBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXCopyFilesBuildPhase section */")
    out.append(build_embed_phase(ids))
    out.append("/* End PBXCopyFilesBuildPhase section */")
    out.append("")
    out.append("/* Begin PBXProject section */")
    out.append(f'\t\t{ids["appProj"]} /* Project object */ = {{')
    out.append('\t\t\tisa = PBXProject;')
    out.append('\t\t\tattributes = {')
    out.append('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
    out.append('\t\t\t\tLastSwiftUpdateCheck = 1500;')
    out.append('\t\t\t\tLastUpgradeCheck = 1500;')
    out.append('\t\t\t\tTargetAttributes = {')
    out.append(f'\t\t\t\t\t{ids["appTarget"]} = {{')
    out.append('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
    out.append('\t\t\t\t\t};')
    out.append(f'\t\t\t\t\t{ids["kbTarget"]} = {{')
    out.append('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
    out.append('\t\t\t\t\t};')
    out.append('\t\t\t\t};')
    out.append('\t\t\t};')
    out.append(f'\t\t\tbuildConfigurationList = {ids["projConfigList"]} /* Build configuration list for PBXProject "ClipBar" */;')
    out.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    out.append('\t\t\tdevelopmentRegion = en;')
    out.append('\t\t\thasScannedForEncodings = 0;')
    out.append('\t\t\tknownRegions = (')
    out.append('\t\t\t\ten,')
    out.append('\t\t\t\tBase,')
    out.append('\t\t\t\t"zh-Hans",')
    out.append('\t\t\t);')
    out.append(f'\t\t\tmainGroup = {ids["mainGroup"]};')
    out.append(f'\t\t\tproductRefGroup = {ids["productsGroup"]} /* Products */;')
    out.append('\t\t\tprojectDirPath = "";')
    out.append('\t\t\tprojectRoot = "";')
    out.append('\t\t\ttargets = (')
    out.append(f'\t\t\t\t{ids["appTarget"]} /* ClipBar */,')
    out.append(f'\t\t\t\t{ids["kbTarget"]} /* ClipBarKeyboard */,')
    out.append('\t\t\t);')
    out.append('\t\t};')
    out.append("/* End PBXProject section */")
    out.append("")
    out.append("")
    out.append("")
    out.append("/* Begin XCBuildConfiguration section */")
    out.append(build_configs(ids))
    out.append("/* End XCBuildConfiguration section */")
    out.append("")
    out.append("/* Begin XCConfigurationList section */")
    out.append(f'\t\t{ids["appConfigList"]} /* Build configuration list for PBXNativeTarget "ClipBar" */ = {{')
    out.append('\t\t\tisa = XCConfigurationList;')
    out.append('\t\t\tbuildConfigurations = (')
    out.append(f'\t\t\t\t{ids["app:Debug"]} /* Debug */,')
    out.append(f'\t\t\t\t{ids["app:Release"]} /* Release */,')
    out.append('\t\t\t);')
    out.append('\t\t\tdefaultConfigurationIsVisible = 0;')
    out.append('\t\t\tdefaultConfigurationName = Release;')
    out.append('\t\t};')
    out.append(f'\t\t{ids["kbConfigList"]} /* Build configuration list for PBXNativeTarget "ClipBarKeyboard" */ = {{')
    out.append('\t\t\tisa = XCConfigurationList;')
    out.append('\t\t\tbuildConfigurations = (')
    out.append(f'\t\t\t\t{ids["kb:Debug"]} /* Debug */,')
    out.append(f'\t\t\t\t{ids["kb:Release"]} /* Release */,')
    out.append('\t\t\t);')
    out.append('\t\t\tdefaultConfigurationIsVisible = 0;')
    out.append('\t\t\tdefaultConfigurationName = Release;')
    out.append('\t\t};')
    out.append(f'\t\t{ids["projConfigList"]} /* Build configuration list for PBXProject "ClipBar" */ = {{')
    out.append('\t\t\tisa = XCConfigurationList;')
    out.append('\t\t\tbuildConfigurations = (')
    out.append(f'\t\t\t\t{ids["proj:Debug"]} /* Debug */,')
    out.append(f'\t\t\t\t{ids["proj:Release"]} /* Release */,')
    out.append('\t\t\t);')
    out.append('\t\t\tdefaultConfigurationIsVisible = 0;')
    out.append('\t\t\tdefaultConfigurationName = Release;')
    out.append('\t\t};')
    out.append("/* End XCConfigurationList section */")
    out.append("\t};")
    out.append(f'\trootObject = {ids["appProj"]} /* Project object */;')
    out.append("}")
    return "\n".join(out)


def main():
    os.makedirs(PROJ, exist_ok=True)
    content = build_project(IDS)
    path = os.path.join(PROJ, "project.pbxproj")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✅ 已生成 {path}（{len(content)} 字节）")


if __name__ == "__main__":
    main()
