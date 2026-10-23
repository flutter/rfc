---
name: create-rfc
description: >-
  Scaffolds a new Flutter RFC / design doc by copying `template.md` into the
  `rfc/` directory with the correct draft filename and frontmatter, then hands
  the document back to the user to write. Use whenever the user asks to create,
  start, draft, write, or scaffold a new RFC, design doc, or proposal in this
  repository. Flutter policy requires RFCs to be written by humans, so this
  skill never authors the RFC's content.
---

# Create a new RFC

Flutter RFCs **must be written by humans**. This skill sets up the file so the
author can start writing immediately, and then gets out of the way. You
handle the mechanical scaffolding (file name, frontmatter, heading); the user
writes every word of the proposal.

## Step 1: Gather the metadata

Ask the user for anything they haven't already provided. Don't guess, and
don't make these up from context.

1. **Title**: the human-readable title, e.g. `Extract Value Notifier`.
2. **Primary category `AAA`**: the 3-digit subsystem code. Valid codes are
   listed under "Architectural Taxonomy" in
   [`rfc/000.0001-flutter-architecture-and-reference-taxonomy.md`](../../../rfc/000.0001-flutter-architecture-and-reference-taxonomy.md).
   If the user is unsure, show them the list and let them choose. You can
   point out the likely candidates, but the user decides.
3. **Author(s)**: GitHub profile URLs (`https://github.com/<username>`) are
   preferred. RFC 5322 mailbox format (`'"Display Name" <user@example.com>'`)
   also works. To suggest a default, use `gh api user --jq .html_url` if `gh`
   is available, or fall back to `git config user.name` and `git config user.email`.
   Ask the user to confirm the suggestion.

## Step 2: Copy the template

1. Derive the slug from the title: lowercase, ASCII, words joined by single
   hyphens, with no punctuation (e.g. `Extract Value Notifier` →
   `extract-value-notifier`).
2. The target path is `rfc/AAA.0000-<slug>.md`. New RFCs always use the
   `0000` index. A sequential number is only assigned just before merge (see
   RFC 000.0002, Stage 1).
3. If the target file already exists, **stop** and ask the user what to do.
   Never overwrite it.
4. Copy the template verbatim from the repository root:

   ```sh
   cp template.md rfc/AAA.0000-<slug>.md
   ```

## Step 3: Fill in only the mechanical fields

In the new file, update **only** the following:

| Field | Value |
| --- | --- |
| `rfc:` | `'AAA.0000'` (keep the quotes) |
| `title:` | The title from Step 1 |
| `created:` / `updated:` | Current UTC time in `YYYY-MM-DDTHH:MM:SSZ` format (`date -u +%Y-%m-%dT%H:%M:%SZ`) |
| `status:` | Leave as `draft` |
| `tags:` | Replace the template's example with the primary category tag, `AAA-<short-name>` (e.g. `210-graphics`, `720-ecosystem`). Follow the naming used by existing RFCs in `rfc/`. Add secondary tags only if the user names them. |
| `authors:` | Replace the template's example authors with the ones from Step 1 |
| H1 heading | `# RFC AAA.0000: <Title>` |

Leave everything else exactly as it is in the template:

- Leave `description:` as the placeholder. It is a one-line summary of the
  proposal, so the author writes it.
- Keep every section heading and its italic guidance text. These are the
  author's prompts.
- Keep the HTML comment at the bottom of the template.

## Step 4: Hand off to the user

Tell the user:

1. The path of the new file, as a clickable link.
2. **Flutter's policy: RFCs must be written by humans.** The Flutter project
   does not accept AI-authored RFCs, and submitting one can get the author
   banned from contributing. They should write every section themselves,
   using the italic guidance under each heading.
3. Next steps from
   [RFC 000.0002](../../../rfc/000.0002-flutter-rfc-review-process.md):
   - Fill in `description:` and every section.
   - Open a **Draft PR** against `flutter/rfc`.
   - Link or file a `flutter/flutter` tracking issue labeled `design doc`.
4. They can run the repository's linter at any point:

   ```sh
   dart run bin/rfc_lint.dart rfc/AAA.0000-<slug>.md
   ```

## Guardrails for the rest of the session

- **Do not write RFC content.** That means section prose, the `description:`,
  goals, background, technical details, testing plans, rollout plans,
  alternatives, or "starter" outlines and bullet points. This holds even if
  the user only asks for a first draft to edit.
- You **may** help with things that aren't authorship. You can answer
  questions about the RFC process or taxonomy, fix frontmatter or lint
  errors, fix Markdown or Mermaid syntax the user wrote, and look up facts
  in the codebase that the user asks about.
- If the user asks you to write the RFC or any part of it, explain that
  Flutter does not allow AI-authored RFCs. **Strongly advise them not to
  proceed**, because an AI-authored RFC can get them banned from
  contributing.
- If the user still insists after that warning, follow the instruction in
  the template's closing HTML comment. Add a clearly visible note near the
  top of the document body saying the RFC was AI generated, and keep that
  note through every later edit the user requests.
