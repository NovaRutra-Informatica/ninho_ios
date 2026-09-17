"""Portable checks of the delivered scaffold, not an Xcode/iOS build."""
import copy
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import generate_project as generator
import select_simulator as simulator


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.project = generator.project()
        self.objects = self.project["objects"]

    def test_generated_files_match_exactly(self):
        for path, data in generator.outputs().items():
            self.assertEqual(path.read_bytes(), data, str(path))

    def test_all_object_references_resolve(self):
        def inspect(value):
            if isinstance(value, dict):
                for child in value.values():
                    inspect(child)
            elif isinstance(value, list):
                for child in value:
                    inspect(child)
            elif isinstance(value, str) and len(value) == 24 and all(c in "ABCDEF0123456789" for c in value):
                self.assertIn(value, self.objects)
        inspect(self.project)

    def test_targets_share_swift6_ios26_iphone_only(self):
        for name in ("Debug", "Release"):
            settings = self.objects[generator.identifier(f"config.project.{name}")]["buildSettings"]
            self.assertEqual(settings["IPHONEOS_DEPLOYMENT_TARGET"], "26.0")
            self.assertEqual(settings["SWIFT_VERSION"], "6.0")
            self.assertEqual(settings["TARGETED_DEVICE_FAMILY"], "1")

    def test_test_targets_are_wired_to_app_and_core(self):
        for name in ("NinhoTests", "NinhoUITests"):
            target = self.objects[generator.identifier(f"target.{name}")]
            dependency = self.objects[target["dependencies"][0]]
            self.assertEqual(dependency["target"], generator.identifier("target.Ninho"))
        package = self.objects[generator.identifier("package")]
        self.assertEqual(package["relativePath"], ".")
        for name in ("Ninho", "NinhoTests"):
            product = self.objects[generator.identifier(f"package-product.{name}")]
            self.assertEqual(product["productName"], "NinhoCore")

    def test_signing_has_no_private_team_and_no_ipad_target(self):
        for name in ("Ninho", "NinhoTests", "NinhoUITests"):
            for config in ("Debug", "Release"):
                settings = self.objects[generator.identifier(f"config.{name}.{config}")]["buildSettings"]
                self.assertEqual(settings["DEVELOPMENT_TEAM"], "")
                self.assertEqual(settings["CODE_SIGN_STYLE"], "Automatic")
                self.assertEqual(settings["SUPPORTS_MACCATALYST"], "NO")

    def test_scheme_runs_both_test_targets_without_skips(self):
        scheme = ET.fromstring(generator.scheme())
        tests = scheme.findall("TestAction/Testables/TestableReference")
        self.assertEqual(len(tests), 2)
        self.assertEqual({item.find("BuildableReference").get("BlueprintName") for item in tests}, {"NinhoTests", "NinhoUITests"})
        self.assertTrue(all(item.get("skipped") == "NO" for item in tests))
        self.assertEqual(scheme.find("TestAction/EnvironmentVariables/EnvironmentVariable").get("value"), "unit-host")
        self.assertIsNone(scheme.find("LaunchAction/CommandLineArguments"))

    def test_manual_workflow_does_not_trigger_on_push_or_sign(self):
        text = (generator.ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", text)
        self.assertIn("run: bash scripts/test-macos.sh", text)
        self.assertIn("path: TestResults/*.xcresult", text)
        self.assertNotIn("pull_request:", text)
        self.assertNotIn("push:", text)
        self.assertNotIn("secrets.", text)

    def test_workflow_pins_actions_and_does_not_persist_checkout_credentials(self):
        text = (generator.ROOT / ".github/workflows/ios.yml").read_text(encoding="utf-8")
        actions = re.findall(r"uses:\s*([^\s#]+)", text)
        self.assertEqual(len(actions), 2)
        for action in actions:
            self.assertRegex(action, r"^actions/(checkout|upload-artifact)@[0-9a-f]{40}$")
        checkout = text.split("uses: actions/checkout@", 1)[1].split("      - name:", 1)[0]
        self.assertIn("persist-credentials: false", checkout)
        self.assertIn("permissions:\n  contents: read\n", text)
        self.assertNotRegex(text, r"(?m)^\s*(contents|actions|id-token|packages|pull-requests):\s*write\s*$")
        self.assertIn("include-hidden-files: false", text)


class XcodeRequirementTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ninho-xcode-requirement-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        (scripts / "common.sh").write_bytes((generator.ROOT / "scripts/common.sh").read_bytes())
        (scripts / "generate_project.py").write_text("print('synthetic project checked')\n", encoding="utf-8")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, body in {
            "uname": "#!/bin/bash\nprintf 'Darwin\\n'\n",
            "plutil": "#!/bin/bash\nprintf 'synthetic plist checked\\n'\n",
            "xcodebuild": '#!/bin/bash\nexec "$NINHO_TEST_PYTHON" "$NINHO_TEST_ROOT/fake_xcodebuild.py" "$@"\n',
        }.items():
            command = self.bin / name
            command.write_text(body, encoding="utf-8")
            command.chmod(0o755)
        (self.root / "fake_xcodebuild.py").write_text(
            "import os, signal, sys\n"
            "from pathlib import Path\n"
            "assert sys.argv[1:] == ['-version']\n"
            "signal.signal(signal.SIGPIPE, signal.SIG_DFL)\n"
            "print('Xcode ' + os.environ['NINHO_TEST_XCODE_VERSION'], flush=True)\n"
            "for _ in range(64):\n"
            "    sys.stdout.buffer.write(b'Build information\\n' * 1024)\n"
            "sys.stdout.flush()\n"
            "Path(os.environ['NINHO_TEST_ROOT'], 'version-output-complete').touch()\n"
            "sys.exit(int(os.environ['NINHO_TEST_XCODE_STATUS']))\n",
            encoding="utf-8",
        )

    def require_xcode(self, version="26.1.1", status=0):
        environment = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ.get('PATH', '')}",
            "NINHO_TEST_PYTHON": sys.executable,
            "NINHO_TEST_ROOT": str(self.root),
            "NINHO_TEST_XCODE_VERSION": version,
            "NINHO_TEST_XCODE_STATUS": str(status),
        }
        return subprocess.run(
            ["bash", "-c", 'source "$1"; require_xcode', "require-xcode-test", str(self.root / "scripts/common.sh")],
            env=environment, capture_output=True, text=True, timeout=30,
        )

    def test_large_version_output_is_drained_without_sigpipe(self):
        result = self.require_xcode()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "version-output-complete").exists())
        self.assertIn("synthetic project checked", result.stdout)
        self.assertIn("synthetic plist checked", result.stdout)
        self.assertTrue((self.root / "TestResults").is_dir())

    def test_old_xcode_is_rejected_after_reading_version(self):
        result = self.require_xcode(version="25.0")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("Xcode 26+", result.stderr)
        self.assertFalse((self.root / "TestResults").exists())

    def test_xcodebuild_failure_still_propagates(self):
        result = self.require_xcode(status=69)
        self.assertEqual(result.returncode, 69, result.stderr)
        self.assertNotIn("synthetic project checked", result.stdout)
        self.assertFalse((self.root / "TestResults").exists())


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
        self.inventory = {"runtimes": [{"identifier": self.runtime, "version": "26.0", "isAvailable": True}], "devices": {self.runtime: []}}

    def device(self, name=simulator.NAME, **changes):
        return {"name": name, "udid": "qa-device", "isAvailable": True, "deviceTypeIdentifier": simulator.DEVICE_TYPE, **changes}

    def test_creates_separate_device_instead_of_reusing_personal_phone(self):
        self.inventory["devices"][self.runtime] = [self.device("My iPhone")]
        self.assertEqual(simulator.select(self.inventory), (None, self.runtime))

    def test_reuses_available_dedicated_device(self):
        self.inventory["devices"][self.runtime] = [self.device()]
        self.assertEqual(simulator.select(self.inventory), ("qa-device", None))

    def test_does_not_reuse_missing_runtime(self):
        self.inventory["runtimes"][0]["isAvailable"] = False
        self.inventory["devices"][self.runtime] = [self.device()]
        with self.assertRaises(ValueError):
            simulator.select(self.inventory)

    def test_override_rejects_wrong_type_old_os_or_unknown_uuid(self):
        cases = [self.device(deviceTypeIdentifier="iPad"), self.device(isAvailable=False)]
        for device in cases:
            self.inventory["devices"][self.runtime] = [device]
            with self.assertRaises(ValueError):
                simulator.select(self.inventory, "qa-device")
        self.inventory["devices"][self.runtime] = [self.device()]
        with self.assertRaises(ValueError):
            simulator.select(self.inventory, "unknown")
        self.inventory["runtimes"][0]["version"] = "18.5"
        with self.assertRaises(ValueError):
            simulator.select(self.inventory, "qa-device")

    def test_newest_available_ios_runtime_is_selected_numerically(self):
        for value in ("26.2", "26.10", "27.0"):
            self.inventory["runtimes"].append({"identifier": f"com.apple.CoreSimulator.SimRuntime.iOS-{value.replace('.', '-')}", "version": value, "isAvailable": value != "27.0"})
        self.assertTrue(simulator.select(self.inventory)[1].endswith("26-10"))

    def test_explicit_available_phone_override_is_honored(self):
        self.inventory["devices"][self.runtime] = [self.device("Explicit QA phone")]
        self.assertEqual(simulator.select(self.inventory, "qa-device"), ("qa-device", None))


if __name__ == "__main__":
    unittest.main()
