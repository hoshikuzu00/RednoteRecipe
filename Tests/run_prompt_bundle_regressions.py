#!/usr/bin/env python3
"""Compile the actual prompt loader into a temporary macOS app bundle and run it.

Requires macOS Command Line Tools or Xcode. Does not launch a UI or call an API.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLT = Path('/Library/Developer/CommandLineTools')
DEVELOPER = Path(os.environ.get('DEVELOPER_DIR', str(CLT)))
if not DEVELOPER.exists():
    DEVELOPER = Path('/Applications/Xcode.app/Contents/Developer')
if (DEVELOPER / 'usr/bin/swiftc').exists():
    compiler = DEVELOPER / 'usr/bin/swiftc'
    sdk = DEVELOPER / 'SDKs/MacOSX.sdk'
else:
    compiler = DEVELOPER / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
    sdk = DEVELOPER / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'

with tempfile.TemporaryDirectory(prefix='rednote-prompts-') as directory:
    root = Path(directory)
    contents = root / 'PromptCheck.app/Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    shutil.copytree(ROOT / 'skills/recipe-post-parser', contents / 'Resources/recipe-post-parser')
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'PromptCheck',
        'CFBundleIdentifier': 'com.test.RednotePromptCheck',
        'CFBundlePackageType': 'APPL',
    }))
    main = root / 'main.swift'
    shutil.copyfile(ROOT / 'Tests/RecipePromptBundleRegression.swift', main)
    executable = contents / 'MacOS/PromptCheck'
    subprocess.run([
        str(compiler), '-sdk', str(sdk), '-module-cache-path', str(root / 'module-cache'),
        str(ROOT / 'Sources/RecipeParserSkillPrompts.swift'), str(main), '-o', str(executable),
    ], env={**os.environ, 'DEVELOPER_DIR': str(DEVELOPER)}, check=True)
    subprocess.run([str(executable)], check=True)
