# Nanobrew UI docs

> Status: current · Owner: Rex57 · Reviewed: 2026-11-05

The map of the docs. It holds no facts of its own: it sends each question to the one page that answers it.

## By question

| Question | Page |
|---|---|
| What is Nanobrew UI, and how do I install or upgrade it? | [README](../README.md#install) |
| How do I build it and run the tests? | [README: Build](../README.md#build), [Testing: Run them](TESTING.md#run-them) |
| How do I try the app without touching my real nanobrew? | [Testing: Manual checks with launch arguments](TESTING.md#manual-checks-with-launch-arguments) |
| How do I drive the running app by AppleScript safely? | [Testing: Driving the app by AppleScript safely](TESTING.md#driving-the-app-by-applescript-safely) |
| How is the app built, and how does it run nb? | [Architecture](ARCHITECTURE.md) |
| Where does a piece of the code live? | [Architecture: Files](ARCHITECTURE.md#files) |
| Which files does the app write? | [Architecture: Where the app writes](ARCHITECTURE.md#where-the-app-writes) |
| What happens when I quit while a command runs? | [Architecture: Quit rules](ARCHITECTURE.md#quit-rules) |
| Why was something built this way (text parsing, ad hoc signing, a zip, no Sparkle)? | [Decisions](DECISIONS.md) |
| What does the app look like, and what do its colours mean? | [Design language](DESIGN.md), [UI prototype](UI/prototype_UI.html) |
| How do I make a release? | [Releasing](RELEASING.md) |
| What does an upgrade need, and why does Gatekeeper block a browser download? | [Releasing: What an upgrade needs](RELEASING.md#what-an-upgrade-needs), [The Gatekeeper limit](RELEASING.md#the-gatekeeper-limit) |
| What changed in each release? | [Changelog](../CHANGELOG.md) |
| What is done, what is open, and what comes next? | [Roadmap](../ROADMAP.md) |

## By reader

- **A user:** [README](../README.md), then the [roadmap](../ROADMAP.md) and the [changelog](../CHANGELOG.md).
- **A contributor:** [README: Build](../README.md#build), [Architecture](ARCHITECTURE.md), [Testing](TESTING.md),
  [Decisions](DECISIONS.md), then [Design language](DESIGN.md) for any screen change.
- **A releaser:** [Releasing](RELEASING.md), then a new entry in the [changelog](../CHANGELOG.md).
- **A designer:** [Design language](DESIGN.md) and the [UI prototype](UI/prototype_UI.html).
- **An agent:** [Architecture](ARCHITECTURE.md) and [Testing](TESTING.md), with its rules for driving the app
  safely, before any change.

## By kind

- **How-to:** [Testing](TESTING.md), [Releasing](RELEASING.md).
- **Reference:** [Architecture](ARCHITECTURE.md) (the code map and the command catalogue),
  [Design language](DESIGN.md) (the tokens and components).
- **Explanation:** [Decisions](DECISIONS.md), the reasons behind each choice.
- **Logs:** [Changelog](../CHANGELOG.md) and [Decisions](DECISIONS.md): new entries are added, old entries keep
  their words.
- **Records:** the [UI prototype](UI/prototype_UI.html), the approved mockups of 2026-11-01, kept as approved.
- **Forward:** the [roadmap](../ROADMAP.md).

## How we keep docs

- Each fact has one home. Every other page links to that home and does not copy it.
- Every page has a status line under its title. `Reviewed` is the day someone last read the whole page against
  the code, not the day of the last edit.
- A new decision is a new numbered entry in [Decisions](DECISIONS.md); a release is a new entry on top of the
  [changelog](../CHANGELOG.md); a change of plans goes in the [roadmap](../ROADMAP.md).
- When code changes a fact a page states (a colour in `Theme.swift`, a command in the catalogue), change the page
  in the same commit.
- `swift test` runs the docs gate (`tools/check_docs.py`): it fails on a broken link or anchor, a page the map
  does not link, or a missing status line.
