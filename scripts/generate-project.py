#!/usr/bin/env python3
"""Generate the small shared Xcode project without a project-generator dependency."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def oid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def obj(label, isa, **values):
    key = oid(label)
    objects[key] = {'isa': isa, **values}
    return key

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

def serialize(value, depth=0):
    indent = '\t' * depth
    if isinstance(value, dict):
        return '{\n' + ''.join(indent + '\t' + quote(k) + ' = ' + serialize(v, depth + 1) + ';\n' for k, v in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(indent + '\t' + serialize(v, depth + 1) + ',\n' for v in value) + indent + ')'
    return quote(value)

def main():
    app_files = sorted(ROOT.glob('App/**/*.swift'))
    engine_files = sorted((ROOT / 'build/engine').rglob('*.cpp'))
    engine_files = [p for p in engine_files if p.name != 'main.cpp' and 'universal' not in p.parts]
    source_files = app_files + [ROOT / 'Engine/PikafishBridge.mm', ROOT / 'Engine/RulesExtension.cpp'] + engine_files
    resources = [ROOT / 'Resources/pikafish.nnue', ROOT / 'Resources/Pikafish-Copying.txt',
                 ROOT / 'Resources/Pikafish-AUTHORS', ROOT / 'Resources/Network-LICENSE.md',
                 ROOT / 'Resources/Network-Upstream-README.md', ROOT / 'Resources/Assets.xcassets']
    references, sources, resource_builds = [], [], []
    for path in source_files + resources + [ROOT / 'Engine/BridgingHeader.h', ROOT / 'Engine/PikafishBridge.h', ROOT / 'App/Info.plist']:
        relative = str(path.relative_to(ROOT))
        ext = path.suffix
        filetype = {'.swift': 'sourcecode.swift', '.cpp': 'sourcecode.cpp.cpp', '.mm': 'sourcecode.cpp.objcpp',
                    '.h': 'sourcecode.c.h', '.xcassets': 'folder.assetcatalog'}.get(ext, 'file')
        ref = obj(relative, 'PBXFileReference', lastKnownFileType=filetype, path=relative, sourceTree='<group>')
        references.append(ref)
        if path in source_files or path in resources:
            build = obj('build:' + relative, 'PBXBuildFile', fileRef=ref)
            (sources if path in source_files else resource_builds).append(build)
    product = obj('product', 'PBXFileReference', explicitFileType='wrapper.application', path='Xiangqi.app', sourceTree='BUILT_PRODUCTS_DIR')
    products = obj('products', 'PBXGroup', children=[product], name='Products', sourceTree='<group>')
    group = obj('mainGroup', 'PBXGroup', children=references + [products], sourceTree='<group>')
    source_phase = obj('sources', 'PBXSourcesBuildPhase', buildActionMask='2147483647', files=sources, runOnlyForDeploymentPostprocessing='0')
    resource_phase = obj('resources', 'PBXResourcesBuildPhase', buildActionMask='2147483647', files=resource_builds, runOnlyForDeploymentPostprocessing='0')
    framework_phase = obj('frameworks', 'PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0')
    common = {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.chiyizi.xiangqi', 'PRODUCT_NAME': 'Xiangqi',
        'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator macosx', 'SDKROOT': 'auto',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'MACOSX_DEPLOYMENT_TARGET': '14.0',
        'TARGETED_DEVICE_FAMILY': '1,2', 'ARCHS': 'arm64', 'SWIFT_VERSION': '5.0',
        'SWIFT_OBJC_BRIDGING_HEADER': 'Engine/BridgingHeader.h',
        'CLANG_CXX_LANGUAGE_STANDARD': 'c++17', 'CLANG_CXX_LIBRARY': 'libc++',
        'CLANG_ENABLE_OBJC_ARC': 'YES', 'GCC_ENABLE_CPP_EXCEPTIONS': 'NO', 'ALWAYS_SEARCH_USER_PATHS': 'NO',
        'GCC_PREPROCESSOR_DEFINITIONS': ['$(inherited)', 'NDEBUG', 'IS_64BIT', 'USE_NEON', 'USE_POPCNT', 'ZSTD_DISABLE_ASM'],
        'HEADER_SEARCH_PATHS': ['$(SRCROOT)/build/engine', '$(SRCROOT)/Engine'],
        'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_FILE': 'App/Info.plist', 'INFOPLIST_KEY_CFBundleDisplayName': '象棋残局',
        'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.board-games',
        'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
        'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': 'UIInterfaceOrientationPortrait',
        'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
        'CODE_SIGN_STYLE': 'Automatic', 'ENABLE_HARDENED_RUNTIME': 'YES',
        'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1',
        'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../Frameworks'],
    }
    configs = []
    for name in ['Debug', 'Release']:
        values = dict(common)
        values.update({'GCC_OPTIMIZATION_LEVEL': '2' if name == 'Debug' else '3',
                       'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
                       'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if name == 'Debug' else '',
                       'DEBUG_INFORMATION_FORMAT': 'dwarf', 'ONLY_ACTIVE_ARCH': 'YES'})
        configs.append(obj('appConfig:' + name, 'XCBuildConfiguration', name=name, buildSettings=values))
    config_list = obj('appConfigs', 'XCConfigurationList', buildConfigurations=configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Debug')
    target = obj('appTarget', 'PBXNativeTarget', name='Xiangqi', buildConfigurationList=config_list,
                 buildPhases=[source_phase, framework_phase, resource_phase], buildRules=[], dependencies=[],
                 productName='Xiangqi', productReference=product, productType='com.apple.product-type.application')
    project_configs = [obj('projectConfig:' + name, 'XCBuildConfiguration', name=name, buildSettings={}) for name in ['Debug', 'Release']]
    project_config_list = obj('projectConfigs', 'XCConfigurationList', buildConfigurations=project_configs,
                              defaultConfigurationIsVisible='0', defaultConfigurationName='Debug')
    project = obj('project', 'PBXProject', attributes={'LastUpgradeCheck': '2640'}, buildConfigurationList=project_config_list,
                  compatibilityVersion='Xcode 14.0', developmentRegion='zh-Hans', knownRegions=['zh-Hans', 'en', 'Base'],
                  mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[target])
    document = {'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': project}
    folder = ROOT / 'Xiangqi.xcodeproj'
    folder.mkdir(exist_ok=True)
    (folder / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + serialize(document) + '\n')
    scheme = folder / 'xcshareddata/xcschemes'
    scheme.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Xiangqi.app" BlueprintName="Xiangqi" ReferencedContainer="container:Xiangqi.xcodeproj"/>'
    (scheme / 'Xiangqi.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
    print(f'Generated Xiangqi.xcodeproj: {len(app_files)} Swift and {len(engine_files)} engine files.')

if __name__ == '__main__':
    main()
