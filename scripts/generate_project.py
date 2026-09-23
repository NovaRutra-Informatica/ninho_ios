#!/usr/bin/env python3
"""Generate the checked-in Xcode project without Xcode or third-party tools.

Xcode 26 reads the filesystem-synchronized source groups. Adding Swift files or
resources beneath Ninho, NinhoWidgets, NinhoTests or NinhoUITests does not require regeneration.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def identifier(name: str) -> str:
    return hashlib.sha256(f"ninho.ios.{name}".encode()).hexdigest()[:24].upper()


def openstep(value: object, level: int = 0) -> str:
    indent = "\t" * level
    if isinstance(value, dict):
        body = "\n".join(
            f"{indent}\t{json.dumps(str(key), ensure_ascii=False)} = {openstep(item, level + 1)};"
            for key, item in value.items()
        )
        return "{\n" + body + "\n" + indent + "}"
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "\n".join(f"{indent}\t{openstep(item, level + 1)}," for item in value) + "\n" + indent + ")"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    raise TypeError(f"Unsupported project value: {value!r}")


def project() -> dict:
    objects: dict[str, dict] = {}

    def add(key: str, isa: str, **properties: object) -> str:
        token = identifier(key)
        assert token not in objects, f"Duplicate object: {key}"
        objects[token] = {"isa": isa, **properties}
        return token

    package = add("package", "XCLocalSwiftPackageReference", relativePath=".")
    llama_package = add("package.llama", "XCLocalSwiftPackageReference", relativePath="Packages/NinhoLlama")
    groups = {
        name: add(f"group.{name}", "PBXFileSystemSynchronizedRootGroup", exceptions=[], explicitFileTypes={}, explicitFolders=[], path=name, sourceTree="<group>")
        for name in ("Ninho", "NinhoWidgets", "NinhoTests", "NinhoUITests")
    }
    products = {}
    for name in groups:
        suffix, file_type = {"Ninho": ("app", "wrapper.application"), "NinhoWidgets": ("appex", "wrapper.app-extension")}.get(name, ("xctest", "wrapper.cfbundle"))
        products[name] = add(f"product.{name}", "PBXFileReference", explicitFileType=file_type, includeInIndex=0, path=f"{name}.{suffix}", sourceTree="BUILT_PRODUCTS_DIR")
    products_group = add("products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
    main_group = add("main-group", "PBXGroup", children=[*groups.values(), products_group], sourceTree="<group>")

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_UNREACHABLE_CODE": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "NINHO_APP_GROUP": "group.com.aless.ninho.ios",
        "NINHO_ICLOUD_CONTAINER": "iCloud.com.aless.ninho.ios",
    }
    target_common = {
        "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "GENERATE_INFOPLIST_FILE": "YES",
        "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0", "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    }

    def configuration_list(key: str, base: dict, project_level: bool = False) -> str:
        configs = []
        for name in ("Debug", "Release"):
            settings = dict(base)
            if project_level:
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O"})
                if name == "Debug":
                    settings.update({"ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES", "GCC_OPTIMIZATION_LEVEL": "0", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG"})
                else:
                    settings.update({"SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
            configs.append(add(f"config.{key}.{name}", "XCBuildConfiguration", buildSettings=settings, name=name))
        return add(f"configs.{key}", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    project_configs = configuration_list("project", common, True)
    target_ids = []
    for name in groups:
        dependencies = []
        package_dependencies = []
        framework_files = []
        if name in ("Ninho", "NinhoTests"):
            product = add(f"package-product.{name}", "XCSwiftPackageProductDependency", package=package, productName="NinhoCore")
            package_dependencies.append(product)
            framework_files.append(add(f"package-build.{name}", "PBXBuildFile", productRef=product))
        if name in ("Ninho", "NinhoWidgets"):
            support = add(f"widget-product.{name}", "XCSwiftPackageProductDependency", package=package, productName="NinhoWidgetSupport")
            package_dependencies.append(support)
            framework_files.append(add(f"widget-build.{name}", "PBXBuildFile", productRef=support))
            exception = add(f"exceptions.{name}", "PBXFileSystemSynchronizedBuildFileExceptionSet", membershipExceptions=["Info.plist", f"{name}.entitlements"], target=identifier(f"target.{name}"))
            objects[groups[name]]["exceptions"].append(exception)
        if name == "Ninho":
            llama = add("llama-product.Ninho", "XCSwiftPackageProductDependency", package=llama_package, productName="NinhoLlama")
            package_dependencies.append(llama)
            framework_files.append(add("llama-build.Ninho", "PBXBuildFile", productRef=llama))
            proxy = add("proxy.widgets", "PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=identifier("target.NinhoWidgets"), remoteInfo="NinhoWidgets")
            dependencies.append(add("dependency.widgets", "PBXTargetDependency", target=identifier("target.NinhoWidgets"), targetProxy=proxy))
        if name in ("NinhoTests", "NinhoUITests"):
            proxy = add(f"proxy.{name}", "PBXContainerItemProxy", containerPortal=identifier("project"), proxyType=1, remoteGlobalIDString=identifier("target.Ninho"), remoteInfo="Ninho")
            dependencies.append(add(f"dependency.{name}", "PBXTargetDependency", target=identifier("target.Ninho"), targetProxy=proxy))
        phases = [
            add(f"sources.{name}", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
            add(f"frameworks.{name}", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=framework_files, runOnlyForDeploymentPostprocessing=0),
            add(f"resources.{name}", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
        ]
        settings = {**target_common, "PRODUCT_BUNDLE_IDENTIFIER": {"Ninho": "com.aless.ninho.ios", "NinhoWidgets": "com.aless.ninho.ios.widgets", "NinhoTests": "com.aless.ninho.ios.tests", "NinhoUITests": "com.aless.ninho.ios.uitests"}[name]}
        product_type = "com.apple.product-type.application"
        if name == "Ninho":
            embed = add("embed.widgets.file", "PBXBuildFile", fileRef=products["NinhoWidgets"], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
            phases.append(add("embed.widgets.phase", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
            settings.update({
                "INFOPLIST_FILE": "Ninho/Info.plist", "CODE_SIGN_ENTITLEMENTS": "Ninho/Ninho.entitlements",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "INFOPLIST_KEY_CFBundleDisplayName": "Ninho", "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.education",
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                "INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace": "YES", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            })
        elif name == "NinhoWidgets":
            product_type = "com.apple.product-type.app-extension"
            settings.update({
                "INFOPLIST_FILE": "NinhoWidgets/Info.plist", "CODE_SIGN_ENTITLEMENTS": "NinhoWidgets/NinhoWidgets.entitlements",
                "INFOPLIST_KEY_CFBundleDisplayName": "Ninho", "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
            })
        else:
            settings["TEST_TARGET_NAME"] = "Ninho"
            settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"
            settings["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"
            if name == "NinhoTests":
                product_type = "com.apple.product-type.bundle.unit-test"
                settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Ninho.app/Ninho"})
            else:
                product_type = "com.apple.product-type.bundle.ui-testing"
        configs = configuration_list(name, settings)
        target_ids.append(add(f"target.{name}", "PBXNativeTarget", buildConfigurationList=configs, buildPhases=phases, buildRules=[], dependencies=dependencies, fileSystemSynchronizedGroups=[groups[name]], name=name, packageProductDependencies=package_dependencies, productName=name, productReference=products[name], productType=product_type))
    attributes = {
        identifier(f"target.{name}"): {"CreatedOnToolsVersion": "26.0", "ProvisioningStyle": "Automatic", **({"TestTargetID": identifier("target.Ninho")} if name in ("NinhoTests", "NinhoUITests") else {"SystemCapabilities": {"com.apple.ApplicationGroups.iOS": {"enabled": 1}}})}
        for name in groups
    }
    root = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "2600", "LastUpgradeCheck": "2600", "TargetAttributes": attributes}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 16.0", developmentRegion="pt-BR", hasScannedForEncodings=0, knownRegions=["pt-BR", "en", "Base"], mainGroup=main_group, minimizedProjectReferenceProxies=1, packageReferences=[package, llama_package], preferredProjectObjectVersion=77, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=target_ids)
    return {"archiveVersion": 1, "classes": {}, "objectVersion": 77, "objects": objects, "rootObject": root}


def scheme() -> bytes:
    root = ET.Element("Scheme", LastUpgradeVersion="2600", version="1.3")

    def reference(parent: ET.Element, name: str) -> None:
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=identifier(f"target.{name}"), BuildableName=f"{name}.{'app' if name == 'Ninho' else 'xctest'}", BlueprintName=name, ReferencedContainer="container:Ninho.xcodeproj")

    action = ET.SubElement(root, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    for name in ("Ninho", "NinhoTests", "NinhoUITests"):
        is_app = "YES" if name == "Ninho" else "NO"
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning=is_app, buildForProfiling=is_app, buildForArchiving=is_app, buildForAnalyzing=is_app)
        reference(entry, name)
    test = ET.SubElement(root, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="NO", codeCoverageEnabled="YES")
    expansion = ET.SubElement(test, "MacroExpansion")
    reference(expansion, "Ninho")
    args = ET.SubElement(test, "CommandLineArguments")
    for value in ("--uitesting", "--disable-ai"):
        ET.SubElement(args, "CommandLineArgument", argument=value, isEnabled="YES")
    environment = ET.SubElement(test, "EnvironmentVariables")
    ET.SubElement(environment, "EnvironmentVariable", key="NINHO_TEST_PROFILE", value="unit-host", isEnabled="YES")
    testables = ET.SubElement(test, "Testables")
    for name in ("NinhoTests", "NinhoUITests"):
        testable = ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO")
        reference(testable, name)
    launch = ET.SubElement(root, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "Ninho")
    profile = ET.SubElement(root, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "Ninho")
    ET.SubElement(root, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(root, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def outputs() -> dict[Path, bytes]:
    return {
        ROOT / "Ninho.xcodeproj/project.pbxproj": ("// !$*UTF8*$!\n" + openstep(project()) + "\n").encode(),
        ROOT / "Ninho.xcodeproj/xcshareddata/xcschemes/Ninho.xcscheme": scheme(),
        ROOT / "Ninho.xcodeproj/project.xcworkspace/contents.xcworkspacedata": b'<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n',
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if checked-in files differ; never write")
    args = parser.parse_args()
    for path, content in outputs().items():
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                raise SystemExit(f"Generated file is out of date: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        print(f"{'Verified' if args.check else 'Wrote'} {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
