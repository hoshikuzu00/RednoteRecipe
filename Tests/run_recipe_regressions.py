#!/usr/bin/env python3
"""Run production recipe model regressions on macOS without UIKit or API access.

Usage: python3 Tests/run_recipe_regressions.py
SWIFT and SDKROOT can select a different installed Swift toolchain and macOS SDK.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEVELOPER = Path('/Applications/Xcode.app/Contents/Developer')
SWIFT = os.environ.get('SWIFT') or str(DEVELOPER / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swift')
SDK = os.environ.get('SDKROOT') or str(DEVELOPER / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
if not Path(SWIFT).exists():
    SWIFT = shutil.which('swift') or 'swift'

# Compile the production model/normalization declarations, not a copied implementation.
# The preceding enhancer uses UIKit and requires an iOS build; these declarations only use Foundation.
enhancer = (ROOT / 'Sources/OpenAIRecipeEnhancer.swift').read_text()
marker = 'enum OpenAIRecipeEnhancerError: LocalizedError {'
if enhancer.count(marker) != 1:
    raise SystemExit('Production model boundary changed; update the regression runner.')
source = '\n'.join([
    (ROOT / 'Sources/RecipeParser.swift').read_text(),
    marker + enhancer.split(marker, 1)[1],
    (ROOT / 'Tests/RecipeNormalizationRegression.swift').read_text(),
])
with tempfile.TemporaryDirectory(prefix='rednote-regressions-') as directory:
    combined = Path(directory) / 'main.swift'
    combined.write_text(source)
    command = [SWIFT, '-module-cache-path', str(Path(directory) / 'module-cache')]
    if Path(SDK).exists():
        command += ['-sdk', SDK]
    subprocess.run(command + [str(combined)], check=True)
