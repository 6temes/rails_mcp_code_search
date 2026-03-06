# Brainstorm: code_index_mcp

**Date:** 2026-03-06
**Status:** Complete

## What We're Building

A Ruby gem (`code_index_mcp`) that provides Cursor-like semantic codebase search for Claude Code. It indexes codebases using AST-aware chunking and vector embeddings, exposed as an MCP server over stdio.

This is a **developer tool** — installed globally (`gem install code_index_mcp`), never added to a project's Gemfile. Similar to ruby-lsp or solargraph.

### Constraints

- **Requires a git repository.** File discovery uses `git ls-files`, smart reindex uses `git diff`. Non-git directories fail fast with a clear error.
- **Ruby 3.4+** required (Prism parser).
- **SQLite WAL mode** required for concurrent read/write (background indexer + search queries). ActiveRecord connection pool sized for threaded access.

### Core Capabilities

- **Semantic search** across codebases via vector similarity (KNN)
- **AST-aware chunking** for Ruby files (Prism parser)
- **Sliding window chunking** for all other file types (JS, TS, ERB, YML, MD)
- **Incremental indexing** — only re-embeds changed files
- **Background indexing** — MCP server starts immediately, indexes async
- **Smart reindex on search** — quick `git diff` check before each search, full incremental in background
- **Local-first** — works offline with local embeddings, OpenAI optional

## Why This Approach

No existing MCP server handles Ruby AST parsing well. By using Prism (Ruby's built-in parser since 3.4), we get accurate semantic chunking for Ruby code without external dependencies. The adapter pattern for embeddings lets developers start with zero-config local embeddings and optionally upgrade to OpenAI for better quality.

## Key Decisions

### Distribution: Global Ruby Gem

Installed globally, not added to project Gemfiles. The gem provides a `bin/code-index-mcp` executable that Claude Code invokes as an MCP server.

### Per-Project Setup: Auto-Detect from Working Directory

The executable takes no arguments — it detects the project from the working directory Claude Code launches it in. One-time global config in `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "code-index": {
      "command": "code-index-mcp"
    }
  }
}
```

Works for every project automatically. DB path (`~/.local/share/code-index-mcp/<sha256-of-cwd>.db`) isolates each project's index.

### Naming: `code_index_mcp` Everywhere

Underscores for gem name, module name, require path, and directory. Standard Ruby convention.

### Parsing Strategy: Prism for Ruby, Sliding Window for Everything Else

- **Ruby files:** Prism AST visitor extracting classes, modules, methods as semantic chunks
- **All other files (JS, TS, ERB, YML, MD):** 50-line sliding window with 10-line overlap
- **Rationale:** Tree-sitter adds significant installation complexity (compiled C libs + language grammars). For Rails apps, Ruby code is where the real value is. Stimulus controllers and other JS/TS files tend to be small enough that sliding windows capture them in 1-2 chunks.

### Parser Registry: Extensible

Design the parser selection to be extensible (registry pattern) so adding language-specific parsers (Python, JS/TS via tree-sitter) is trivial later. Don't build them now.

### Indexing: Background + Smart Reindex

- **On first start:** Index the entire codebase in a background thread. Server starts immediately and returns partial results / "still indexing" status.
- **On subsequent starts:** Incremental index in background (mtime/sha256 check).
- **Before each search:** Quick check via `git diff --name-only` to reindex recently changed files synchronously. Queue a full incremental check in background if >60 seconds since last full check.

### Embeddings: Adapter Pattern with Local Default

- **Default:** `informers` gem with all-MiniLM-L6-v2 (384 dimensions). Zero config, no API key.
- **Optional:** OpenAI text-embedding-3-small (1536 dimensions) via `ruby-openai` gem.
- Switching providers triggers a full reindex (different dimensions).
- Embedding dimensions stored in metadata table to detect mismatches.

### Search Results: Chunk + Metadata

Return chunk content along with file path, line range, chunk type, and qualified name. Let the agent decide whether to `Read` the full file for more context. No surrounding context lines — keeps token usage efficient.

### Search Filtering: Relevance Only

No chunk type filtering (method, class, etc.). Vector similarity handles it — search for a class name and you get the class. Keep the tool interface simple.

### Usage Statistics: Counters + Top Chunks

- Simple counters in metadata table: total searches, total reindexes, last timestamps
- `hit_count` column on chunks table, incremented each time a chunk appears in search results
- `status` tool exposes "most referenced chunks" — useful for understanding agent behavior

### Storage: SQLite + sqlite-vec via Neighbor

- One DB per project at `~/.local/share/code-index-mcp/<sha256-of-project-path>.db`
- `vec0` virtual table for KNN search (raw SQL, not AR migrations)
- Embeddings stored as blobs: `Array#pack("e*")` (little-endian 32-bit float)

### Stack

| Component | Choice |
|---|---|
| MCP framework | fast-mcp (~> 1.6) |
| Vector storage | SQLite + sqlite-vec via neighbor gem |
| ORM | ActiveRecord standalone (no Rails) |
| Ruby AST | Prism (Ruby 3.4+ default parser) |
| Embeddings | ruby-openai + informers (adapter pattern) |
| File discovery | git ls-files |

### Configuration

- **Project-level:** `.code-index.yml` in project root (optional). Controls embedding provider, include/exclude file patterns.
- **Env vars:** `OPENAI_API_KEY`, `CODE_INDEX_PROVIDER`, `CODE_INDEX_DB_PATH` (override defaults).
- **Defaults:** local embeddings, standard include patterns (`**/*.rb`, `**/*.erb`, `**/*.js`, `**/*.yml`), standard excludes (`vendor/**`, `node_modules/**`, `tmp/**`).

### MCP Tools

Three tools exposed:
- **search:** query (required), limit (optional, default 10), file_pattern (optional glob filter)
- **reindex:** full (optional bool, default false)
- **status:** no args — file/chunk counts, db size, provider info, top chunks, search stats

## Open Questions

*None — all questions resolved during brainstorm.*

## Resolved Questions

1. **How to handle slow local embeddings on large codebases?** Background indexing — server starts immediately, indexes async.
2. **Gem naming convention?** `code_index_mcp` with underscores everywhere.
3. **JS/TS parsing approach?** Sliding window. Stimulus controllers are small enough. Tree-sitter adds too much installation complexity.
4. **Auto-reindex strategy?** Quick `git diff` check before each search + async full incremental in background.
5. **Python support?** Not now, but parser registry designed for extensibility.
6. **Search result format?** Chunk content + metadata. Agent reads full file if needed.
7. **Type filtering?** No — vector similarity handles relevance.
8. **Usage statistics?** Local only. Simple counters + hit_count on chunks.
9. **Distribution format?** Global Ruby gem. Not a project dependency.
