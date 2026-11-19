#!/usr/bin/env python3
# The docs site builder (T4.8, decision D10): plain Markdown, zero site
# framework. Every .md under docs/ renders through one template — a nav
# sidebar, readable on mobile — into docs-site/site/, and the build FAILS
# on a dead relative link, so navigation can never rot silently.
#
#   python3 docs-site/build.py            # build + link check
#   docs-site/preview.sh                  # build + serve on 127.0.0.1:8080
#
# The only dependency is the `markdown` package (GitHub Pages installs it
# the same way; see .github/workflows/docs.yaml). The source Markdown stays
# under docs/ for review — this script never edits it.

import html
import re
import sys
from pathlib import Path

import markdown

REPO = Path(__file__).resolve().parent.parent
DOCS = REPO / "docs"
OUT = Path(__file__).resolve().parent / "site"

# The navigation: (title, [(page relative to docs/, label)]). The first
# section is the landing page's body.
SECTIONS = [
    ("Getting started", [
        ("install.md", "Installation"),
        ("getting-started.md", "Quick start"),
        ("getting-started.zh-CN.md", "快速开始"),
        ("ci/github-actions.md", "Publishing with CI"),
    ]),
    ("Reference", [
        ("cli.md", "CLI reference"),
        ("spec/config.md", "Client configuration"),
    ]),
    ("Specifications", [
        ("spec/README.md", "Spec index"),
        ("spec/pokerface-yaml.md", "pokerface.yaml"),
        ("spec/build-plan.md", "The build plan"),
        ("spec/push.md", "The push pipeline"),
        ("spec/pokerface-lock.md", "pokerface.lock.yaml"),
        ("spec/pull.md", "The pull chain"),
        ("spec/errors.md", "Errors and exit codes"),
    ]),
    ("Registry", [
        ("spec/registry-config.md", "Configuration"),
        ("spec/registry-db.md", "Storage"),
        ("spec/registry-uploads.md", "Uploads"),
        ("spec/registry-manifests.md", "Manifests"),
        ("spec/registry-auth.md", "Authentication"),
        ("spec/registry-metrics.md", "Metrics"),
        ("registry/deployment.md", "Deployment"),
    ]),
    ("Project", [
        ("adr/0001-build-trigger.md", "ADR 0001: build triggers"),
        ("ci/gitlab-ci.md", "GitLab CI"),
        ("ci/gitea-actions.md", "Gitea Actions"),
        ("TASKS.md", "Task plan"),
    ]),
]

CSS = """
:root { --ink: #1f2430; --accent: #2563a8; --side: #f4f6fa; --line: #d9dfe8; }
* { box-sizing: border-box; }
body { margin: 0; color: var(--ink); font: 16px/1.65 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
nav { background: var(--side); border-right: 1px solid var(--line); padding: 1.25rem; width: 15rem; position: fixed; top: 0; bottom: 0; left: 0; overflow-y: auto; }
nav h1 { font-size: 1.05rem; margin: 0 0 1rem; }
nav h1 a { color: var(--ink); text-decoration: none; }
nav h2 { font-size: .8rem; letter-spacing: .06em; text-transform: uppercase; color: #5b6575; margin: 1.1rem 0 .3rem; }
nav a { display: block; color: var(--accent); text-decoration: none; padding: .12rem 0; font-size: .92rem; }
nav a.here { font-weight: 600; }
main { margin-left: 15rem; padding: 2rem 3rem 4rem; max-width: 54rem; }
h1 { font-size: 1.7rem; border-bottom: 2px solid var(--line); padding-bottom: .4rem; }
h2 { margin-top: 2rem; }
pre { background: #f4f6fa; border: 1px solid var(--line); border-radius: 6px; padding: .8rem 1rem; overflow-x: auto; font-size: .88rem; }
code { background: #f4f6fa; padding: .1rem .3rem; border-radius: 4px; font-size: .9em; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 1rem 0; }
th, td { border: 1px solid var(--line); padding: .4rem .7rem; text-align: left; }
blockquote { border-left: 4px solid var(--accent); margin: 1rem 0; padding: .2rem 1rem; color: #445; background: var(--side); }
@media (max-width: 900px) {
  nav { position: static; width: auto; border-right: none; border-bottom: 1px solid var(--line); }
  main { margin-left: 0; padding: 1.2rem 1.2rem 3rem; }
}
"""

TEMPLATE = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · pokerface</title>
<style>{css}</style>
<nav>
<h1><a href="{home}">pokerface</a></h1>
{nav}
</nav>
<main>
{body}
</main>
"""

MD = markdown.Markdown(extensions=["tables", "fenced_code"])


def title_of(md_text: str, path: Path) -> str:
    match = re.search(r"^#\s+(.+)$", md_text, re.M)
    if match:
        return match.group(1).strip()
    return path.stem.replace("-", " ").replace("_", " ").capitalize()


def depth_prefix(rel: str) -> str:
    # The site mirrors docs/, so a page at depth n climbs n levels to the
    # root; GitHub Pages serves project sites under a subpath, which is why
    # everything stays relative.
    depth = rel.count("/")
    return "../" * depth


def nav_link(page: str, label: str, here: str, prefix: str) -> str:
    cls = ' class="here"' if page == here else ""
    return f'<a{cls} href="{prefix}{page[:-3]}.html">{html.escape(label)}</a>'


def render_nav(here: str) -> str:
    prefix = depth_prefix(here)
    out = []
    for section, pages in SECTIONS:
        out.append(f"<h2>{html.escape(section)}</h2>")
        for page, label in pages:
            out.append(nav_link(page, label, here, prefix))
    return "\n".join(out)


def rewrite_hrefs(body: str) -> str:
    # The source Markdown links sibling pages as *.md; the mirrored site
    # serves *.html, so the generated hrefs get the suffix swapped.
    return re.sub(r'(href=")((?:\.\./)?[^":#]+)\.md(")', r"\1\2.html\3", body)


def convert(path: Path) -> str:
    md_text = path.read_text(encoding="utf-8")
    MD.reset()
    return MD.convert(md_text)


def link_targets(md_text: str) -> list[str]:
    # Markdown links minus images; only relative document targets matter.
    out = []
    for match in re.finditer(r"\[([^\]]*)\]\(([^)]+)\)", md_text):
        target = match.group(2).strip()
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        out.append(target.split("#")[0])
    return out


def main() -> int:
    OUT.mkdir(exist_ok=True)
    errors = []

    # Every page the nav names must exist.
    for _, pages in SECTIONS:
        for page, _ in pages:
            if not (DOCS / page).is_file():
                errors.append(f"nav: docs/{page} does not exist")

    count = 0
    for md_path in sorted(DOCS.rglob("*.md")):
        rel = str(md_path.relative_to(DOCS))
        text = md_path.read_text(encoding="utf-8")
        for target in link_targets(text):
            if not target:
                continue
            resolved = (md_path.parent / target).resolve()
            if not resolved.is_file():
                errors.append(f"docs/{rel}: dead link '{target}'")

        dest = OUT / Path(rel).with_suffix(".html")
        dest.parent.mkdir(parents=True, exist_ok=True)
        prefix = depth_prefix(rel)
        home = prefix + "index.html"
        dest.write_text(
            TEMPLATE.format(
                title=html.escape(title_of(text, md_path)),
                css=CSS,
                home=home,
                nav=render_nav(rel),
                body=rewrite_hrefs(convert(md_path)),
            ),
            encoding="utf-8",
        )
        count += 1

    # The landing page: a short index of the sections with their pages.
    items = []
    for section, pages in SECTIONS:
        entries = "".join(
            f'<li>{nav_link(page, label, "", "")}</li>' for page, label in pages
        )
        items.append(f"<h2>{html.escape(section)}</h2><ul>{entries}</ul>")
    landing = (
        "<h1>pokerface documentation</h1>"
        "<p>pokerface distributes container images through Git: an "
        "application repository commits <code>pokerface.yaml</code>, CI "
        "builds and pushes with <code>pokerface build</code>, and the "
        "registry serves images to <code>pokerface resolve</code> and "
        "<code>pokerface pull</code> consumers. Start with the "
        "installation, then the quick start, then the specs.</p>"
        + "".join(items)
    )
    (OUT / "index.html").write_text(
        TEMPLATE.format(
            title="Documentation",
            css=CSS,
            home="index.html",
            nav=render_nav(""),
            body=landing,
        ),
        encoding="utf-8",
    )
    count += 1

    if errors:
        print("docs-site: the build found problems:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(f"docs-site: built {count} pages into docs-site/site (links ok)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
