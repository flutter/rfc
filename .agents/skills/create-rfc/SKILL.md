---
name: create-rfc
description: >-
  Scaffolds a new Flutter RFC / design doc by copying
  `rfc/000.0003-rfc-template.md` to a new file in the `rfc/` directory with
  the correct draft filename and frontmatter, then hands
  the document back to the user to write. Use whenever the user asks to create,
  start, draft, write, or scaffold a new RFC, design doc, or proposal in this
  repository. Flutter's CLA requires a submitted RFC to be the contributor's
  original creation, so this skill never generates the RFC's content.
---

# Create a new RFC

Flutter's CLA requires that what a contributor submits is **their own
original creation**. Requests that would violate the CLA must be refused,
and you should take care to help the user avoid negative repercussions. A
human has to make every important editorial decision, and reviewers
shouldn't be the first humans to try to understand the RFC in detail. See
[CONTRIBUTING.ai.md](https://github.com/flutter/flutter/blob/master/CONTRIBUTING.ai.md)
for the project's full AI policy.

This skill sets up the file so the author can start writing right away, then
gets out of the way. You handle the mechanical scaffolding (file name,
frontmatter, heading). The user authors the proposal: the ideas, the design,
the decisions, and the prose.

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
4. Copy the template verbatim:

   ```sh
   cp rfc/000.0003-rfc-template.md rfc/AAA.0000-<slug>.md
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
- Keep the italic "Guidelines for good RFCs" list, every section heading, and
  each section's italic guidance text. These are the author's prompts.
- Keep the HTML comment at the bottom of the template.

## Step 4: Hand off to the user

Tell the user:

1. The path of the new file, as a clickable link.
2. **Flutter's AI policy.** This is a strong warning. The CLA requires the
   submitted RFC to be their own original creation. Frame this as helping
   them avoid negative repercussions, not as a threat. They need to make all
   the important editorial decisions themselves, and to understand every
   part of the document in detail before a reviewer sees it. Point them to
   [CONTRIBUTING.ai.md](https://github.com/flutter/flutter/blob/master/CONTRIBUTING.ai.md)
   for details.
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

The test is whether the RFC stays the user's original creation, with the
user making every important editorial decision.

- **Do not generate novel RFC content.** Don't produce the substance of the
  proposal: section prose, the `description:`, goals, background, the design,
  testing or rollout plans, or alternatives. 
- You **may** help in ways that leave the authorship and decisions with the
  user. For example, you can:
  - Answer questions about the RFC process, the taxonomy, or the codebase.
  - Fix frontmatter, lint errors, and Markdown or Mermaid syntax the user
    wrote.
  - Review the user's draft the way a colleague would. Point out unclear
    passages, gaps, inconsistencies, or likely reviewer questions, and let
    the user decide what to change and write the changes.
  - Suggest small wording or grammar fixes to the user's own sentences,
    which the user accepts or rejects one by one.
  - Help non-native English speakers and authors draft, translate, or tighten
    prose from their ideas so the document is concise and easy to read.
  - Convert a user's existing design doc into the RFC template sections.
- If a request would make you the author of the proposal, **refuse it**.
  Requests that violate the CLA must be refused, not fulfilled with a
  disclaimer. Explain why, with care to help the user avoid negative
  repercussions, point them to
  [CONTRIBUTING.ai.md](https://github.com/flutter/flutter/blob/master/CONTRIBUTING.ai.md),
  and offer the kinds of help listed above instead.
