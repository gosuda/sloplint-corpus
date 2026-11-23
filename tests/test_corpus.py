# SPDX-License-Identifier: MIT
"""Tests for tools/corpus/corpus. Run: python3 tests/test_corpus.py"""
import hashlib
import importlib.util
import json
import os
import shutil
import re
import stat
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(REPO, "tools", "corpus", "corpus")
ASKALONO = "/dev/shm/CorpusTooling/tools/bin/askalono"
HAS_ASKALONO = os.path.isfile(ASKALONO) and os.access(ASKALONO, os.X_OK)
HAS_GIT = shutil.which("git") is not None

MIT_TEXT = """MIT License

Copyright (c) 2026 sloplint corpus synthetic fixture

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def load_tool():
    spec = importlib.util.spec_from_loader("corpus_tool", loader=None)
    module = importlib.util.module_from_spec(spec)
    with open(TOOL, encoding="utf-8") as fh:
        source = fh.read()
    code = compile(source, TOOL, "exec")
    exec(code, module.__dict__)
    return module


corpus = load_tool()


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(content, bytes) else "w"
    with open(path, mode) as fh:
        fh.write(content)


def make_repo(mode="public"):
    root = tempfile.mkdtemp(prefix="corpus-test-")
    write(os.path.join(root, "corpus.toml"),
          'schema_version = 1\n\n[corpus]\nmode = "%s"\n' % mode)
    return root


def add_synthetic_project(root, lang="rust", name="demo", spdx="MIT", storage="copied",
                          files=None):
    projdir = os.path.join(root, "projects", lang, name)
    os.makedirs(projdir)
    if files is None:
        if lang == "rust":
            files = {
                "src/lib.rs": "pub fn add(left: u64, right: u64) -> u64 {\n    left + right\n}\n",
                "src/util.rs": "pub fn double(value: u64) -> u64 {\n    value * 2\n}\n",
                "tests/basic.rs": "#[test]\nfn adds() {\n    assert_eq!(crate::add(1, 2), 3);\n}\n",
            }
        else:
            files = {
                "pkg/mod.py": "def add(left, right):\n    return left + right\n",
                "pkg/util.py": "def double(value):\n    return value * 2\n",
                "tests/test_basic.py": "def test_adds():\n    assert 1 + 2 == 3\n",
            }
    for rel, content in files.items():
        write(os.path.join(projdir, rel), content)
    if storage == "copied":
        write(os.path.join(projdir, "LICENSE"), MIT_TEXT)
        write(os.path.join(projdir, "UPSTREAM.md"),
              "# Upstream provenance\n\nurl: https://example.com/demo\n")
    tree_hash = corpus.compute_tree_hash(projdir)
    entry = ('\n[[project]]\nname = "%s"\nlanguage = "%s"\n'
             'url = "https://example.com/demo"\n'
             'rev = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n'
             'spdx = "%s"\nstorage = "%s"\npaths = ["src/**"]\n'
             'tree_hash = "%s"\nadded_by = "tester"\n'
             'added_on = "2026-11-23"\nreason = "synthetic test fixture"\n'
             'notice_present_upstream = false\n' % (name, lang, spdx, storage, tree_hash))
    with open(os.path.join(root, "corpus.toml"), "a", encoding="utf-8") as fh:
        fh.write(entry)
    return projdir

def run_tool(root, *argv):
    cmd = [sys.executable, TOOL, argv[0]]
    cmd.extend(argv[1:])
    cmd.extend(["--root", root])
    env = dict(os.environ)
    if HAS_ASKALONO:
        env["CORPUS_ASKALONO"] = ASKALONO
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env=env)
    return proc


class TestSpdx(unittest.TestCase):
    def test_or_expression(self):
        self.assertEqual(corpus.spdx_ids("MIT OR Apache-2.0"), {"MIT", "Apache-2.0"})

    def test_with_exception(self):
        self.assertEqual(corpus.spdx_ids("Apache-2.0 WITH LLVM-exception"), {"Apache-2.0"})

    def test_public_allowlist(self):
        self.assertTrue(corpus.public_spdx_ok("MIT"))
        self.assertTrue(corpus.public_spdx_ok("MIT OR Apache-2.0"))
        self.assertTrue(corpus.public_spdx_ok("(MIT OR Apache-2.0)"))
        self.assertFalse(corpus.public_spdx_ok("MIT AND BSD-3-Clause"))
        self.assertFalse(corpus.public_spdx_ok("MIT AND Apache-2.0"))
        self.assertFalse(corpus.public_spdx_ok("Apache-2.0 WITH LLVM-exception"))
        self.assertFalse(corpus.public_spdx_ok("MIT WITH nonallowlisted-exception"))
        self.assertFalse(corpus.public_spdx_ok("GPL-3.0-only"))
        self.assertFalse(corpus.public_spdx_ok("NOASSERTION"))
        self.assertFalse(corpus.public_spdx_ok("MIT OR"))

    def test_and_header_fails_public(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root, files={
            "src/lib.rs": "// SPDX-License-Identifier: MIT AND Apache-2.0\n"
                          "pub fn f() {}\n"})
        errors = []
        corpus.check_headers(projdir, "rust", {"MIT", "Apache-2.0"}, True, errors,
                             "project demo")
        self.assertTrue(any("outside the public allowlist" in e for e in errors), errors)

    def test_noassertion_ids(self):
        self.assertEqual(corpus.spdx_ids("NOASSERTION"), {"NOASSERTION"})


class TestGlobs(unittest.TestCase):
    def test_double_star_spans_directories(self):
        self.assertTrue(corpus.match_subset("src/lib.rs", ["src/**"]))
        self.assertTrue(corpus.match_subset("src/net/tcp.rs", ["src/**"]))
        self.assertTrue(corpus.match_subset("src/a/b/c.rs", ["src/**"]))

    def test_patterns_anchor_at_root(self):
        self.assertFalse(corpus.match_subset("vendor/src/x.rs", ["src/**"]))
        self.assertFalse(corpus.match_subset("examples/src/demo.rs", ["src/**", "tests/**"]))

    def test_excludes_span_directories(self):
        self.assertTrue(corpus.match_subset("vendor/a/b.rs", ["vendor/**"]))
        self.assertFalse(corpus.match_subset("src/lib.rs", ["vendor/**"]))

    def test_single_star_stays_within_a_segment(self):
        self.assertTrue(corpus.match_subset("src/lib.rs", ["src/*.rs"]))
        self.assertFalse(corpus.match_subset("src/net/tcp.rs", ["src/*.rs"]))


class TestHeaders(unittest.TestCase):
    def test_clean_headers_pass(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        errors = []
        corpus.check_headers(projdir, "rust", {"MIT"}, True, errors, "project demo")
        self.assertEqual(errors, [])

    def test_gpl_header_fails_public(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root, files={
            "src/lib.rs": ("// Copyright (C) 2026 demo\n"
                           "// This program is free software: you can redistribute it under\n"
                           "// the terms of the GNU General Public License as published by\n"
                           "// the Free Software Foundation.\n"
                           "pub fn f() {}\n")})
        errors = []
        corpus.check_headers(projdir, "rust", {"MIT"}, True, errors, "project demo")
        self.assertTrue(any("copyleft" in e for e in errors), errors)

    def test_spdx_header_mismatch_fails_private(self):
        root = make_repo(mode="private")
        self.addCleanup(shutil.rmtree, root, True)
        tag_line = "// SPDX-License" + "-Identifier: GPL-3.0-only\n"
        projdir = add_synthetic_project(root, files={"src/lib.rs": tag_line + "pub fn f() {}\n"})
        errors = []
        corpus.check_headers(projdir, "rust", {"MIT"}, False, errors, "project demo")
        self.assertTrue(any("outside declared spdx" in e for e in errors), errors)

    def test_secrets_found(self):
        key = b"aws_key = AKIA" + b"IOSFODNN7EXAMPLE\n"
        hits = corpus.scan_secrets(key)
        self.assertEqual(hits, ["aws-access-key"])
        self.assertEqual(corpus.scan_secrets(b"nothing here\n"), [])

    def test_tree_hash_stable(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        first = corpus.compute_tree_hash(projdir)
        self.assertTrue(first.startswith("sha256:"))
        self.assertEqual(first, corpus.compute_tree_hash(projdir))


class TestVerify(unittest.TestCase):
    def test_missing_manifest_fails(self):
        root = tempfile.mkdtemp(prefix="corpus-test-")
        self.addCleanup(shutil.rmtree, root, True)
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("manifest file not found", proc.stdout)

    def test_empty_public_repo_passes(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        proc = run_tool(root, "verify", "--offline")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("PASS verify", proc.stdout)

    def test_non_allowlisted_spdx_fails_public(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, spdx="BSD-3-Clause")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not on the public allowlist", proc.stdout)

    def test_missing_license_fails(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        os.remove(os.path.join(projdir, "LICENSE"))
        path = os.path.join(root, "corpus.toml")
        manifest = open(path).read()
        tree_hash = corpus.compute_tree_hash(projdir)
        manifest = re.sub(r'tree_hash = "sha256:[0-9a-f]+"',
                          'tree_hash = "%s"' % tree_hash, manifest)
        open(path, "w").write(manifest)
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no LICENSE", proc.stdout)

    def test_hash_mismatch_fails(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        with open(os.path.join(projdir, "src", "extra.rs"), "w") as fh:
            fh.write("pub fn g() {}\n")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("tree_hash mismatch", proc.stdout)

    def test_oversize_file_fails(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        with open(os.path.join(projdir, "src", "big.rs"), "wb") as fh:
            fh.write(b"x" * (corpus.MAX_FILE_BYTES + 1))
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("above the", proc.stdout)

    def test_bad_extension_fails(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root)
        write(os.path.join(projdir, "notes.txt"), "hello\n")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not allowlisted", proc.stdout)

    def test_pinned_with_files_fails_private(self):
        root = make_repo(mode="private")
        self.addCleanup(shutil.rmtree, root, True)
        projdir = add_synthetic_project(root, name="pin", spdx="NOASSERTION",
                                        storage="pinned")
        write(os.path.join(projdir, "src", "x.py"), "x = 1\n")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("pinned entry must have no files", proc.stdout)

    def test_public_spdx_in_private_fails(self):
        root = make_repo(mode="private")
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, spdx="MIT")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("belongs in the public repo", proc.stdout)

    def test_unindexed_project_dir_fails(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        write(os.path.join(root, "projects", "rust", "unindexed", "src", "lib.rs"),
              "// SPDX-License-Identifier: GPL-3.0-only\npub fn f() {}\n")
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not owned by a copied manifest entry", proc.stdout)

    def test_removed_entry_leaves_unowned_dir(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, name="demo")
        manifest = open(os.path.join(root, "corpus.toml")).read()
        open(os.path.join(root, "corpus.toml"), "w").write(
            "schema_version = 1\n\n[corpus]\nmode = \"public\"\n")
        self.assertIn("demo", manifest)
        proc = run_tool(root, "verify", "--offline")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not owned by a copied manifest entry", proc.stdout)


    @unittest.skipUnless(HAS_ASKALONO, "askalono binary not installed")
    def test_clean_tree_passes(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, lang="rust", name="syn-rust")
        add_synthetic_project(root, lang="python", name="syn-python")
        proc = run_tool(root, "verify", "--offline")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("PASS verify: 2 project(s)", proc.stdout)


def make_local_git_repo(license_text):
    upstream = tempfile.mkdtemp(prefix="corpus-upstream-")
    subprocess.run(["git", "init", "-q", upstream], check=True, timeout=60)
    write(os.path.join(upstream, "src", "lib.rs"),
          "pub fn add(left: u64, right: u64) -> u64 {\n    left + right\n}\n")
    write(os.path.join(upstream, "src", "util.rs"),
          "pub fn double(value: u64) -> u64 {\n    value * 2\n}\n")
    write(os.path.join(upstream, "LICENSE"), license_text)
    subprocess.run(["git", "-C", upstream, "add", "-A"], check=True, timeout=60)
    subprocess.run(["git", "-C", upstream, "-c", "user.name=t", "-c", "user.email=t@t",
                    "commit", "-qm", "fixture"], check=True, timeout=60)
    rev = subprocess.run(["git", "-C", upstream, "rev-parse", "HEAD"],
                         capture_output=True, text=True, check=True,
                         timeout=60).stdout.strip()
    return upstream, rev


class TestAddLocal(unittest.TestCase):
    @unittest.skipUnless(HAS_GIT and HAS_ASKALONO, "needs git and askalono")
    def test_add_local_repo_green(self):
        upstream, rev = make_local_git_repo(MIT_TEXT)
        self.addCleanup(shutil.rmtree, upstream, True)
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        proc = run_tool(root, "add", "--url", upstream, "--rev", rev,
                        "--lang", "rust", "--spdx", "MIT", "--name", "local-demo",
                        "--paths", "src/**", "--reason", "local fixture")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("PASS add: projects/rust/local-demo", proc.stdout)
        projdir = os.path.join(root, "projects", "rust", "local-demo")
        self.assertTrue(os.path.isfile(os.path.join(projdir, "src", "lib.rs")))
        self.assertTrue(os.path.isfile(os.path.join(projdir, "src", "util.rs")))
        self.assertTrue(os.path.isfile(os.path.join(projdir, "LICENSE")))
        self.assertTrue(os.path.isfile(os.path.join(projdir, "UPSTREAM.md")))
        manifest = open(os.path.join(root, "corpus.toml")).read()
        self.assertIn('url = "file://%s"' % upstream, manifest)
        self.assertEqual(run_tool(root, "verify", "--offline").returncode, 0)

    @unittest.skipUnless(HAS_GIT, "needs git")
    def test_add_gpl_refused_public(self):
        upstream = tempfile.mkdtemp(prefix="corpus-upstream-")
        self.addCleanup(shutil.rmtree, upstream, True)
        write(os.path.join(upstream, "LICENSE"),
              "GNU GENERAL PUBLIC LICENSE, version 3 (stub for refusal test)\n")
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        proc = run_tool(root, "add", "--url", upstream,
                        "--rev", "b" * 40, "--lang", "rust",
                        "--spdx", "GPL-3.0-only", "--name", "gpl-demo",
                        "--paths", "src/**", "--reason", "copyleft fixture")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not on the public allowlist", proc.stdout)

    @unittest.skipUnless(HAS_GIT, "needs git")
    def test_add_pinned_no_files(self):
        upstream, rev = make_local_git_repo(MIT_TEXT)
        self.addCleanup(shutil.rmtree, upstream, True)
        root = make_repo(mode="private")
        self.addCleanup(shutil.rmtree, root, True)
        proc = run_tool(root, "add", "--url", upstream, "--rev", rev,
                        "--lang", "rust", "--spdx", "NOASSERTION",
                        "--name", "pin-demo", "--storage", "pinned",
                        "--paths", "src/**", "--reason", "unlicensed fixture")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("PASS add: pinned pin-demo", proc.stdout)
        self.assertFalse(os.path.exists(
            os.path.join(root, "projects", "rust", "pin-demo")))
        fetch = run_tool(root, "fetch", "--lang", "rust", "--allow-unlicensed")
        self.assertEqual(fetch.returncode, 0, fetch.stdout + fetch.stderr)
        check = run_tool(root, "fetch", "--check", "--allow-unlicensed")
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    @unittest.skipUnless(HAS_GIT, "needs git")
    def test_add_quoted_reason_keeps_manifest_parsable(self):
        upstream, rev = make_local_git_repo(MIT_TEXT)
        self.addCleanup(shutil.rmtree, upstream, True)
        root = make_repo(mode="private")
        self.addCleanup(shutil.rmtree, root, True)
        reason = 'Tests the "fast path" parser \\ nightly\nsecond line'
        proc = run_tool(root, "add", "--url", upstream, "--rev", rev,
                        "--lang", "rust", "--spdx", "NOASSERTION",
                        "--name", "quote-demo", "--storage", "pinned",
                        "--paths", "src/**", "--reason", reason)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        import tomllib
        with open(os.path.join(root, "corpus.toml"), "rb") as fh:
            data = tomllib.load(fh)
        self.assertEqual(data["project"][0]["reason"], reason)
        self.assertEqual(run_tool(root, "verify", "--offline").returncode, 0)

    def test_toml_basic_escapes_round_trip(self):
        import tomllib
        for raw in ['plain', 'a"b', "back\\slash", "new\nline", "tab\there",
                    "ctrl\x01x", "uni\x7fh", "snow\xe2\x9d\x83"]:
            doc = 'v = "%s"\n' % corpus._toml_basic(raw)
            self.assertEqual(tomllib.loads(doc)["v"], raw)


FAKE_SLOPLINT = """#!/bin/sh
cat <<'EOF'
{"version":1,
 "findings":[{"rule":"meta/parse-error","severity":"minor","confidence":"high",
   "path":"src/broken.rs","line":2,"column":1,"message":"m","fix":"f",
   "context":"c","fingerprint":"h"}],
 "rules":{"meta/parse-error":"x"},
 "summary":{"strictness":"standard","files":3,"findings":1,"blocker":0,
   "critical":0,"major":0,"minor":1,"info":0,"baselined":0,"stale":0,"skipped":0}}
EOF
"""


class TestMeasureSeeds(unittest.TestCase):
    def test_measure_aggregates_and_budgets(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, lang="rust", name="syn-rust")
        fake = os.path.join(root, "fake-sloplint")
        write(fake, FAKE_SLOPLINT.encode())
        os.chmod(fake, os.stat(fake).st_mode | stat.S_IEXEC)
        proc = run_tool(root, "measure", "rust", "--sloplint", fake)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        with open(os.path.join(root, "reports", "rust.json"), encoding="utf-8") as fh:
            report = json.load(fh)
        self.assertEqual(report["files"], 3)
        self.assertEqual(report["parse_errors"], 1)
        self.assertEqual(report["findings_per_rule"], {"meta/parse-error": 1})
        with open(os.path.join(root, "budgets.toml"), "w", encoding="utf-8") as fh:
            fh.write("[rust]\nmax_parse_error_per_file = 0.0\n"
                     "max_parse_error_per_kb = 0.0\nmax_panics = 0\n"
                     "max_wall_ms_per_mb = 999999999\nmin_projects = 1\n")
        proc = run_tool(root, "measure", "rust", "--sloplint", fake)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("max_parse_error_per_file", proc.stdout)

    def test_seeds_deterministic(self):
        root = make_repo()
        self.addCleanup(shutil.rmtree, root, True)
        add_synthetic_project(root, lang="python", name="syn-python")
        out1 = os.path.join(root, "seeds1")
        out2 = os.path.join(root, "seeds2")
        self.assertEqual(run_tool(root, "seeds", "python", "--out", out1).returncode, 0)
        self.assertEqual(run_tool(root, "seeds", "python", "--out", out2).returncode, 0)
        first = {n: open(os.path.join(out1, n), "rb").read() for n in sorted(os.listdir(out1))}
        second = {n: open(os.path.join(out2, n), "rb").read() for n in sorted(os.listdir(out2))}
        self.assertEqual(first, second)
        self.assertTrue(first)


if __name__ == "__main__":
    unittest.main(verbosity=2)
