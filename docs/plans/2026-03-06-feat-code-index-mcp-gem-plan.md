---
title: "feat: Build code_index_mcp Ruby Gem"
type: feat
status: completed
date: 2026-03-06
origin: docs/brainstorms/2026-03-06-code-index-mcp-brainstorm.md
---

# Build code_index_mcp Ruby Gem

## Overview

Build a globally-installed Ruby gem (`code_index_mcp`) that provides Cursor-like semantic codebase search for Claude Code. The gem indexes codebases using AST-aware chunking (Prism for Ruby, sliding window for everything else) and vector embeddings (local by default, OpenAI optional), exposed as an MCP server over stdio via fast-mcp.

This is a **developer tool** — installed globally (`gem install code_index_mcp`), never added to a project's Gemfile. Similar to ruby-lsp or solargraph. It auto-detects the project from the working directory Claude Code launches it in.

## Problem Statement

Claude Code lacks semantic codebase search. It relies on grep-style tools (Glob, Grep) that require knowing exact identifiers. No existing MCP server handles Ruby AST parsing well. Cursor's codebase indexing provides a significant productivity advantage — this gem brings similar capability to Claude Code.

## Proposed Solution

A standalone Ruby gem providing three MCP tools (`search`, `reindex`, `status`) over stdio transport. Uses Prism (Ruby 3.4+ built-in parser) for accurate Ruby AST chunking, with a sliding window fallback for all other file types. SQLite + sqlite-vec for vector storage, with background indexing so the server starts immediately.

Key architectural choices (see brainstorm: `docs/brainstorms/2026-03-06-code-index-mcp-brainstorm.md`):

- **Adapter pattern** for embedding providers — local default (informers, 384 dims), OpenAI optional (text-embedding-3-small, 1536 dims). Provider selected via `CODE_INDEX_PROVIDER` env var.
- **Simple parser dispatch** — `if .rb then Prism else sliding window`. Registry pattern deferred until more parsers exist.
- **Usage metrics** — search counters, reindex counters, hit_count per chunk for understanding agent behavior.
- **Background worker as sole writer** — all DB writes go through the background thread. Search is truly read-only.
- **Per-project SQLite DB** at `~/.local/share/code-index-mcp/<sha256-of-cwd>.db`
- **Runtime composition root** — `CodeIndexMcp::Runtime` initializes all subsystems; tools receive collaborators via injection for testability.

## Technical Approach

### Architecture

```text
bin/code-index-mcp (executable)
  |
  v
lib/code_index_mcp.rb (entry point, requires all modules)
  |
  +-- runtime.rb         # Composition root: owns config, database, indexer, embeddings lifecycle
  +-- server.rb          # FastMcp::Server setup, tool registration, stdio start
  +-- database.rb        # ActiveRecord standalone setup, sqlite-vec loading, WAL mode
  |
  +-- tools/
  |   +-- search_tool.rb    # FastMcp::Tool — query + KNN search (read-only)
  |   +-- reindex_tool.rb   # FastMcp::Tool — manual reindex trigger
  |   +-- status_tool.rb    # FastMcp::Tool — index state + health
  |
  +-- indexer.rb             # Orchestrator: file discovery, parse dispatch, embed, store
  +-- background_worker.rb   # Thread-based background indexing (sole DB writer)
  |
  +-- ruby_parser.rb         # Prism AST visitor (classes, modules, methods)
  +-- sliding_window_parser.rb  # 50-line window, 10-line overlap
  |
  +-- embeddings/
  |   +-- adapter.rb         # Base interface: embed(texts) → Array[Array[Float]]
  |   +-- local_adapter.rb   # informers + all-MiniLM-L6-v2 (384 dims)
  |   +-- openai_adapter.rb  # ruby-openai + text-embedding-3-small (1536 dims)
  |
  +-- chunk.rb       # ActiveRecord model with has_neighbors + hit_count
  +-- version.rb     # ENV-driven version
```

### Stack

| Component | Choice | Notes |
|---|---|---|
| MCP framework | fast-mcp (~> 1.6) | Dry-Schema args, annotations, stdio transport |
| Vector storage | SQLite + sqlite-vec via neighbor | vec0 virtual table, KNN with cosine distance |
| ORM | ActiveRecord (standalone) | Connection pool for threaded access |
| Ruby AST | Prism | Built into Ruby 3.4+, no external dependency |
| Local embeddings | informers gem | all-MiniLM-L6-v2, 384 dimensions, zero config |
| OpenAI embeddings | ruby-openai gem | text-embedding-3-small, 1536 dimensions (optional) |
| File discovery | git ls-files | Tracked + untracked (excluding ignored) |

### Database Schema

```sql
CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL,
  line_start INTEGER NOT NULL,
  line_end INTEGER NOT NULL,
  chunk_type TEXT NOT NULL,  -- 'method', 'class', 'module', 'window'
  qualified_name TEXT,        -- 'MyModule::MyClass#my_method'
  content TEXT NOT NULL,
  checksum TEXT NOT NULL,     -- SHA256 of content for dedup
  hit_count INTEGER DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_chunks_file_path ON chunks(file_path);
CREATE INDEX IF NOT EXISTS idx_chunks_hit_count ON chunks(hit_count DESC);

-- Virtual table for vector search
-- Dimensions match active provider: 384 (local) or 1536 (OpenAI)
-- Provider switch triggers DROP + re-CREATE of this table + full reindex
CREATE VIRTUAL TABLE IF NOT EXISTS chunk_embeddings USING vec0(
  chunk_id INTEGER PRIMARY KEY NOT NULL,
  embedding float[384] distance_metric=cosine
);

-- Metadata key-value store
CREATE TABLE IF NOT EXISTS metadata (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
-- Keys: schema_version, embedding_dimensions, embedding_provider,
--        indexed_commit_sha, last_full_check_at, project_path,
--        total_searches, total_reindexes, last_search_at, last_reindex_at
```

### Concurrency Model

**The background worker is the sole writer to SQLite.** This eliminates write contention entirely:

- **Background worker thread:** Owns all INSERT/UPDATE/DELETE operations on chunks and chunk_embeddings. Commits in batches of 50-100 chunks to keep write locks short.
- **Main thread (MCP tools):** Read-only queries. Search does KNN queries. Status reads metadata.
- **Smart reindex on search:** Instead of writing directly, the main thread enqueues changed file paths into the background worker's queue and waits with a short timeout (200ms). If the worker completes within the budget, search uses fresh results. Otherwise, returns stale results with `results_may_be_stale: true`.
- **Thread-safe state:** Background worker exposes `state` (`:idle`, `:indexing`, `:error`), `progress` (float 0.0-1.0), and `errors` (array) via Mutex-protected accessors.
- **Graceful shutdown:** `at_exit` hook + signal trapping (`SIGTERM`, `SIGINT`). Background worker checks `@stop_requested` between files. Main thread waits with 5s timeout before force-closing.

### Implementation Phases

#### Phase 1: Foundation + Parsers + Embeddings

**Goal:** Gem skeleton, database layer, parsers, embeddings, and FastMcp stdio validation.

**Tasks:**

- [x] Initialize git repository
- [x] Scaffold gem structure
  - `code_index_mcp.gemspec`
  - `Gemfile`
  - `Rakefile`
  - `lib/code_index_mcp.rb`
  - `lib/code_index_mcp/version.rb` — `ENV.fetch("CODE_INDEX_MCP_VERSION", "0.0.0.dev")`
  - `bin/code-index-mcp`
  - `.gitignore`, `.ruby-version` (3.4.x)
- [x] Create CLAUDE.md with project conventions (Minitest, DHH style, etc.)
- [x] Implement `lib/code_index_mcp/database.rb`
  - `establish_connection` with pool: 5, timeout: 5000ms
  - WAL mode + `PRAGMA synchronous=NORMAL` + `PRAGMA cache_size=-64000`
  - sqlite-vec extension loading via `configure_connection` on SQLite3Adapter
  - `Neighbor::SQLite.initialize!` after connection
  - Schema creation (idempotent with `IF NOT EXISTS`)
  - DB directory: `~/.local/share/code-index-mcp/` with **0700 permissions** + `.noindex` file (macOS Spotlight exclusion)
  - DB path: `<dir>/<Digest::SHA256.hexdigest(Dir.pwd)>.db` with **0600 permissions**
  - Overridable via `CODE_INDEX_DB_PATH` env var
  - Store `project_path: Dir.pwd` in metadata at creation time
- [x] Implement `lib/code_index_mcp/chunk.rb` — ActiveRecord model with `has_neighbors :embedding`, `hit_count` column
- [x] Implement `lib/code_index_mcp/ruby_parser.rb`
  - Prism AST visitor extracting: classes, modules, methods (instance + class)
  - Each chunk: `{ content:, line_start:, line_end:, chunk_type:, qualified_name: }`
  - Qualified names: `MyModule::MyClass#instance_method`, `MyModule::MyClass.class_method`
  - Handle nested classes/modules (scope stack)
  - **Fallback:** If Prism raises a parse error, fall back to `SlidingWindowParser` for that file
  - Ruby DSL code (has_many, validates, scope) included as part of the containing class chunk
- [x] Implement `lib/code_index_mcp/sliding_window_parser.rb`
  - 50-line windows, 10-line overlap
  - Chunk type: `"window"`, qualified name: `nil`
  - Skip empty files (0 bytes → 0 chunks)
  - Cap at 200 chunks max per file
- [x] Implement `lib/code_index_mcp/embeddings/adapter.rb` — base interface: `embed(texts) → Array[Array[Float]]`, `dimensions → Integer`
- [x] Implement `lib/code_index_mcp/embeddings/local_adapter.rb`
  - `Informers.pipeline("embedding", "sentence-transformers/all-MiniLM-L6-v2")`
  - Lazy-load model on first embed call (not at server startup)
  - Initialize model once, reuse across calls (thread-safe for reads)
  - 384 dimensions, L2-normalized
  - Handle model download failure: raise descriptive error, don't crash server
  - Batch embedding: accept array of texts, return array of vectors
- [x] Implement `lib/code_index_mcp/embeddings/openai_adapter.rb`
  - `ruby-openai` client with `text-embedding-3-small` (1536 dimensions)
  - Batch embedding (multiple texts per API call, batch by token budget ~100k tokens)
  - Retry on 429 (rate limit) with exponential backoff, max 3 retries
  - Raise on 401/403 with clear "invalid API key" message
  - **API key safety:** Read from `OPENAI_API_KEY` env var once at init. Wrap API calls to sanitize error messages — strip any string matching `sk-*` pattern before propagating to Layer 1.
  - **Never log or expose the API key** in status tool, errors, or stderr
- [x] Provider selection via `CODE_INDEX_PROVIDER` env var (`local` default, `openai` optional)
  - On first OpenAI use for a project, log stderr warning: "Source code from this repository will be sent to OpenAI's embedding API."
  - Dimension mismatch detection: if metadata `embedding_dimensions` differs from active provider, trigger full reindex (DROP + re-CREATE vec0 table)
- [x] **Validate FastMcp early:** Implement minimal `lib/code_index_mcp/server.rb` + `lib/code_index_mcp/tools/status_tool.rb` returning `{ "state": "initializing" }`
  - Verify stdio transport works end-to-end with Claude Code
  - Catch FastMcp API issues before building the full pipeline

**Success criteria:**
- [x] `bundle exec ruby -e "require 'code_index_mcp'"` loads without error
- [x] Database creates with WAL mode, sqlite-vec loaded, correct permissions
- [x] Ruby parser correctly chunks a Rails model with nested class, methods, DSL calls
- [x] Sliding window parser produces correct overlapping chunks
- [x] Prism parse error on invalid Ruby falls back to sliding window
- [x] Local adapter generates 384-dim vectors
- [x] OpenAI adapter generates 1536-dim vectors (integration test, skipped without API key)
- [x] Provider switch triggers full reindex with vec0 table recreation
- [x] Minimal MCP server starts and responds to status tool over stdio
- [x] Tests: database creation, parser output, embedding dimensions, adapter dispatch, FastMcp smoke test

#### Phase 2: Indexer + Background Worker + MCP Tools

**Goal:** Full indexing pipeline, background worker, and all three MCP tools wired up.

**Tasks:**

- [x] Implement `lib/code_index_mcp/indexer.rb`
  - File discovery: `git ls-files` + `git ls-files --others --exclude-standard`
    - **All git commands use array-form execution:** `Open3.capture2("git", "ls-files")` — never shell string interpolation
    - **Symlink traversal protection:** After discovery, reject files where `File.realpath(path)` resolves outside repo root
    - Fail fast with clear error if not in a git repository
    - Skip non-UTF-8 files with warning logged to stderr
  - Hardcoded include patterns: `**/*.rb`, `**/*.erb`, `**/*.js`, `**/*.ts`, `**/*.yml`, `**/*.md`
  - Hardcoded exclude patterns: `vendor/**`, `node_modules/**`, `tmp/**`, `log/**`
  - Parse dispatch: `path.end_with?(".rb") ? RubyParser : SlidingWindowParser`
  - Orchestrate: discover files → filter → parse → embed → store
  - Incremental: check file mtime + SHA256 checksum, skip unchanged files
  - Track indexing errors per file (don't skip silently — accumulate in array)
  - On provider switch (dimension mismatch in metadata): drop all chunks + embeddings, recreate vec0 table with new dimensions, full reindex
  - Batch embedding calls (32-64 chunks for local, token-budget batching for OpenAI)
  - **Commit to DB in batches of 50-100 chunks** (keep write locks short)
  - Store indexed commit SHA, embedding dimensions, and provider name in metadata
- [x] Implement `lib/code_index_mcp/background_worker.rb`
  - `Thread.new` with `ActiveRecord::Base.connection_pool.with_connection`
  - **Sole writer to SQLite** — all DB mutations go through this thread
  - Run full index on first start, incremental on subsequent starts
  - Accept enqueued work from main thread via `Queue`
  - Thread-safe state via Mutex: `state` (`:idle`, `:indexing`, `:error`), `progress` (float), `errors` (array)
  - **Graceful shutdown:** `at_exit` + signal trapping (SIGTERM, SIGINT). Check `@stop_requested` between files. Main thread waits 5s before force-close.
  - **Reindex cooldown:** Ignore `full: true` requests within 60 seconds of last full reindex
  - **Batched hit_count updates:** Main thread enqueues chunk IDs to increment; worker applies as single `UPDATE chunks SET hit_count = hit_count + 1 WHERE id IN (...)` statement
  - **Batched metric updates:** Worker periodically flushes accumulated `total_searches` and `total_reindexes` counters to metadata table
- [x] Implement smart reindex logic (method on indexer, not a separate class)
  - `git diff --name-only HEAD` via `Open3.capture2` to find changed files
  - **Cache git diff result for 3 seconds** to avoid redundant shell-outs on rapid successive searches
  - **Time budget:** Enqueue changed files to background worker, wait up to 200ms. If worker completes within budget, search uses fresh results. Otherwise return stale results with `results_may_be_stale: true`.
  - Track `last_full_check_at` in metadata; if > 60 seconds, queue full incremental in background
- [x] Implement `lib/code_index_mcp/runtime.rb`
  - Composition root: creates and wires database, embedding adapter (based on `CODE_INDEX_PROVIDER`), indexer, background worker
  - Tools receive collaborators via injection (not global lookup)
  - Single entry point: `Runtime.boot` returns configured runtime
- [x] Complete `lib/code_index_mcp/tools/search_tool.rb`

  ```ruby
  class SearchTool < FastMcp::Tool
    description "Search the codebase using semantic similarity. Use this when you need to find " \
                "code by concept or behavior (e.g., 'authentication logic', 'payment processing') " \
                "rather than by exact identifier. For exact string matches, prefer Grep. " \
                "Returns code chunks ranked by cosine similarity. " \
                "Scores above 0.7 are typically strong matches, 0.5-0.7 are partial matches."

    annotations(
      title: "Search Code",
      read_only_hint: true,
      idempotent_hint: true,
      open_world_hint: false
    )

    arguments do
      required(:query).filled(:string).description("Search query (natural language or code)")
      optional(:limit).filled(:integer).description("Max results (default 10)")
      optional(:file_pattern).filled(:string).description(
        "Glob pattern to filter results by file path (e.g. 'app/models/**/*.rb'). " \
        "Applied after similarity search — may return fewer results than limit."
      )
    end
  end
  ```

  - Trigger smart reindex (enqueue to background worker, wait up to 200ms)
  - Generate query embedding
  - **Verify sqlite-vec LIMIT pushdown:** Confirm `Chunk.nearest_neighbors(:embedding, vec, distance: "cosine").first(limit)` pushes `k=limit` to vec0. If not, use raw SQL: `SELECT * FROM chunk_embeddings WHERE embedding MATCH ? AND k = ?`
  - **Over-fetch for file_pattern:** If file_pattern present, fetch `limit * 5` from KNN, filter by glob, truncate to `limit`. Include `filtered_out_count` in metadata.
  - **Post-search dedup:** Collapse results from same file with overlapping line ranges into one result spanning the full range.
  - **Metrics:** Enqueue hit_count increments for returned chunk IDs to background worker. Increment in-memory `total_searches` counter (flushed to metadata by worker).
  - **Structured error responses:**
    ```json
    {
      "error": "index_empty",
      "message": "No files indexed yet. The index is still building — try again in a moment, or call reindex.",
      "recoverable": true,
      "suggested_action": "reindex"
    }
    ```
    Error categories: `index_empty`, `indexing_in_progress`, `model_downloading`, `database_error`

  **Response schema:**

  ```json
  {
    "results": [
      {
        "file_path": "app/models/user.rb",
        "line_start": 15,
        "line_end": 42,
        "chunk_type": "class",
        "qualified_name": "User",
        "content": "class User < ApplicationRecord\n  ...",
        "similarity": 0.87
      }
    ],
    "metadata": {
      "query": "user authentication",
      "limit": 10,
      "count": 5,
      "has_more": false,
      "index_state": "ready",
      "index_completeness": 1.0,
      "results_may_be_stale": false,
      "total_indexed_chunks": 1234,
      "filtered_out_count": 0
    }
  }
  ```

- [x] Complete `lib/code_index_mcp/tools/reindex_tool.rb`

  ```ruby
  class ReindexTool < FastMcp::Tool
    description "Trigger codebase reindex. Use full=true to rebuild the entire index. " \
                "Returns immediately — use the status tool to check progress."

    annotations(
      title: "Reindex Code",
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    arguments do
      optional(:full).filled(:bool).description("Full reindex (default: incremental)")
    end
  end
  ```

  - Enqueues work to background worker, returns immediately
  - 60-second cooldown on `full: true` — returns "reindex recently completed" if within cooldown
  - Response: `{ "status": "reindex_started", "mode": "full|incremental", "estimated_files": 150 }`

- [x] Complete `lib/code_index_mcp/tools/status_tool.rb`

  ```ruby
  class StatusTool < FastMcp::Tool
    description "Show index health and readiness. Use to check if indexing is complete " \
                "before searching, or to diagnose issues."

    annotations(
      title: "Index Status",
      read_only_hint: true,
      idempotent_hint: true,
      open_world_hint: false
    )
  end
  ```

  - Response: top-level `state` enum (`"ready"`, `"indexing"`, `"empty"`, `"error"`, `"model_downloading"`), chunk count, file count, DB size, index completeness (float), embedding provider + dimensions, indexing errors (if any), project path, search stats (total_searches, total_reindexes, last timestamps), top 5 chunks by hit_count
  - **Never expose OPENAI_API_KEY** — only show provider name

- [x] Wire everything in `server.rb`: `Runtime.boot` → register tools → `server.start`
- [x] Implement `bin/code-index-mcp` executable with logging to stderr

**Success criteria:**
- [x] Full lifecycle: index sample project → search → verify results
- [x] Smart reindex: modify file → search → verify fresh results within 200ms budget
- [x] Background worker: indexes without blocking MCP tool responses
- [x] Concurrent access: background indexer running → search query → no SQLite lock errors
- [x] Graceful shutdown: SIGTERM → worker stops cleanly → DB not corrupted
- [x] Non-git directory: immediate structured error, not crash
- [x] Symlink outside repo: rejected by file discovery
- [x] Tests: full pipeline, tool argument validation, error responses, background worker lifecycle

#### Phase 3: Polish + Release

**Goal:** Production-ready gem with documentation and CI.

**Tasks:**

- [x] Add `.rubocop.yml` (DHH/37signals style)
- [x] README.md
  - Installation: `gem install code_index_mcp`
  - Claude Code config: `~/.claude/settings.json` with `code-index-mcp` command
  - Env vars: `CODE_INDEX_PROVIDER`, `OPENAI_API_KEY`, `CODE_INDEX_DB_PATH`, `CODE_INDEX_LOG_LEVEL`
  - Note about first-run model download (~80MB)
  - Privacy notice: OpenAI provider sends source code chunks to OpenAI's embedding API
- [x] Logging: `Logger.new($stderr)` with `CODE_INDEX_LOG_LEVEL` env var (default: `info`)
- [x] GitHub Actions CI: `gem-push.yml` with version from git tag
- [x] Integration test: index a real sample project, search, verify results
- [x] Edge case handling:
  - Non-git directory: fail fast with structured error
  - Empty project (no matching files): return empty results, status shows `state: "empty"`
  - Very large files (>200 chunks): cap and log warning
  - File encoding: skip non-UTF-8 with warning

**Success criteria:**
- [x] Gem installs globally and works from Claude Code
- [x] All tests pass
- [x] CI pipeline runs tests and publishes to RubyGems on tag

## Alternative Approaches Considered

| Approach | Why Rejected |
|---|---|
| Tree-sitter for all languages | Significant installation complexity (compiled C libs + language grammars). Ruby code is where the real value is for Rails apps. (see brainstorm) |
| In-memory vector search (no SQLite) | Doesn't persist across server restarts. Re-embedding entire codebase on every start is too slow. |
| Faiss or Hnswlib | Additional native dependencies. sqlite-vec is lighter and aligns with the SQLite-everything approach. |
| Rails engine instead of standalone gem | This is a developer tool, not a web app. ActiveRecord standalone is sufficient. |
| Project dependency (in Gemfile) | Would pollute project dependencies. Global install like solargraph/ruby-lsp is the right pattern. |
| `.code-index.yml` config file in v1 | YAGNI. Hardcoded defaults cover 95% of use cases. Deferring eliminates YAML trust boundary issues (untrusted repos). Env vars sufficient for provider selection. |
| Parser registry pattern | Only 2 parsers exist. A simple `if` statement suffices. Add registry when more parsers are built. |

## System-Wide Impact

### Interaction Graph

Server start → `Runtime.boot` (database setup: establish_connection, WAL mode, sqlite-vec, schema) → `BackgroundWorker.start` (Thread.new → Indexer.index_all) → `FastMcp::Server.start` (blocks on stdio).

Search tool call → enqueue changed files to BackgroundWorker (wait 200ms budget) → `EmbeddingAdapter.embed(query)` → `Chunk.nearest_neighbors` → dedup overlapping results → enqueue hit_count updates to worker → serialize response.

### Error Propagation

- **Layer 1 (MCP tools):** Rescue `StandardError`, return structured error response (`{ error:, message:, recoverable:, suggested_action: }`). Never crash the server.
- **Layer 2 (internals):** Propagate errors. Parser failures, embedding failures, DB errors bubble up to Layer 1.
- **Background worker:** Catches errors per-file, accumulates in `@errors` array, continues with remaining files. Exposed via status tool.
- **sqlite-vec extension load failure:** Fatal — server cannot function. Raise immediately with descriptive error.

### State Lifecycle Risks

- **Partial indexing failure:** Some files indexed, others failed. Status tool reports `state: "error"` with error details. Next reindex retries failed files.
- **Provider switch mid-index:** Dimension mismatch detected at startup → full wipe and reindex (atomic: DROP vec0 + DELETE chunks in transaction, then recreate). No partial state possible.
- **DB corruption:** Server fails on next query. User deletes DB file, server recreates on restart.
- **Orphaned databases:** Project directory moves → new DB created, old one abandoned. `project_path` stored in metadata enables future cleanup tooling. No cleanup command in v1 (known gap).

### API Surface Parity

Three MCP tools. No other interfaces. CLI is just the MCP server executable — no subcommands in v1.

### Integration Test Scenarios

1. **Full lifecycle:** Start server → index sample project → search → verify results contain expected chunks → reindex → search again → verify updated results
2. **Smart reindex:** Index project → modify a file → search → verify reindex within 200ms budget
3. **Provider switch:** Index with local → set `CODE_INDEX_PROVIDER=openai` → restart → verify full reindex triggered with 1536-dim vec0 table
4. **Concurrent access:** Background indexer running → search query arrives → verify no SQLite lock errors
5. **Non-git directory:** Start server in non-git dir → verify structured error response, not crash
6. **Symlink traversal:** Repo with symlink to `~/.ssh/id_rsa` → verify file rejected by discovery
7. **Metrics:** Search multiple times → verify hit_count incremented on returned chunks → status shows search count

## Acceptance Criteria

### Functional Requirements

- [x] `gem install code_index_mcp` installs globally and `code-index-mcp` is available in PATH
- [x] Server starts via stdio when Claude Code launches it
- [x] Indexes Ruby files using Prism AST (classes, modules, methods as chunks)
- [x] Indexes non-Ruby files using 50-line sliding windows with 10-line overlap
- [x] Generates embeddings using informers (local, zero config) by default
- [x] Optionally uses OpenAI embeddings when `CODE_INDEX_PROVIDER=openai` is set
- [x] Provider switch detects dimension mismatch and triggers full reindex
- [x] Stores embeddings in sqlite-vec with cosine distance
- [x] Background indexes on first start without blocking MCP protocol
- [x] Smart reindex enqueues to background worker with 200ms time budget before each search
- [x] Search returns chunks ranked by similarity with file path, line range, chunk type, qualified name, content, and similarity score
- [x] Search tool description guides agent on when to use it vs Grep/Glob
- [x] Structured error responses with error category, message, recoverable flag, and suggested action
- [x] Reindex tool enqueues to background worker and returns immediately
- [x] Reindex has 60-second cooldown on full reindex
- [x] Status tool reports state enum, chunk count, file count, completeness, provider, errors, search stats, top chunks by hit_count
- [x] Fails fast with structured error in non-git directories
- [x] Symlinks resolving outside repo root rejected by file discovery

### Non-Functional Requirements

- [x] Search completes in < 1 second for projects with < 50k chunks
- [x] Smart reindex adds at most 200ms to search latency
- [x] Background indexing does not block MCP tool responses
- [x] Background worker is the sole SQLite writer — no write contention
- [x] SQLite busy timeout of 5000ms as safety net
- [x] Data directory permissions 0700, DB file permissions 0600
- [x] OPENAI_API_KEY never logged, never in error messages, never in status tool output
- [x] Logs to stderr (stdout reserved for MCP stdio transport)
- [x] Ruby 3.4+ required (Prism dependency)
- [x] Graceful shutdown on SIGTERM/SIGINT — no SQLite corruption

### Quality Gates

- [x] Minitest test suite with > 80% coverage on core paths
- [x] Tests use real SQLite files (not `:memory:`) with real sqlite-vec
- [x] Tests parse real Ruby code with Prism (not mocked ASTs)
- [x] CI runs on push via GitHub Actions
- [x] README documents installation, first-run model download, and OpenAI privacy implications

## Success Metrics

- Search returns relevant results for natural language queries against a Rails codebase
- Indexing completes in < 5 minutes for a 1,000-file project with local embeddings
- Server starts and responds to first search within 2 seconds (returning partial results if indexing)
- Zero crashes during normal usage (all errors caught at Layer 1)

## Dependencies & Prerequisites

| Dependency | Version | Purpose |
|---|---|---|
| Ruby | >= 3.4.0 | Prism parser built-in |
| fast-mcp | ~> 1.6 | MCP server framework |
| activerecord | ~> 8.0 | Standalone ORM |
| sqlite3 | ~> 2.0 | SQLite adapter |
| neighbor | ~> 0.5 | Vector search via sqlite-vec |
| sqlite-vec | (via neighbor) | KNN search extension |
| informers | ~> 1.0 | Local embeddings (384-dim, all-MiniLM-L6-v2) |
| ruby-openai | ~> 7.0 | Optional OpenAI embeddings (1536-dim) |

**Runtime prerequisite:** Project must be a git repository (`git ls-files` for file discovery, `git diff` for smart reindex).

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| informers model download fails (offline/firewall) | Medium | High — server can't embed | Structured error via status tool. Document `XDG_CACHE_HOME` for pre-downloading. Lazy-load model. |
| sqlite-vec native extension fails on a platform | Low | Critical — gem unusable | neighbor gem bundles sqlite-vec. Test on macOS + Linux in CI. |
| sqlite-vec LIMIT not pushed down through neighbor gem | Medium | High — search >1s at scale | Verify during Phase 2. Fallback to raw SQL KNN query if needed. |
| Large codebase (>10k files) slow to index | Medium | Medium — poor first experience | Background indexing + progress in status tool. Batch embeddings (32-64 chunks). |
| SQLite write contention | Low | Low — sole-writer model prevents | Background worker is sole writer. Busy timeout 5000ms as safety net. |
| Prism API changes in future Ruby versions | Low | Medium — parser breaks | Pin to Prism's stable visitor API. Test on latest Ruby in CI. |
| fast-mcp breaking changes | Low | Medium — server breaks | Pin ~> 1.6. Validate early in Phase 1. Monitor changelog. |
| OpenAI API key leaked in error messages | Low | High — credential exposure | Sanitize all error messages from ruby-openai. Strip `sk-*` patterns. Never log key. |
| Source code sent to OpenAI unintentionally | Medium | High — privacy violation | Stderr warning on first OpenAI use per project. Document in README. Provider requires explicit env var. |

## Future Considerations (v2+)

- **`.code-index.yml` config file:** Per-project include/exclude patterns, provider override. Requires YAML trust boundary design (safe_load, pattern validation, restricted keys).
- **Parser registry:** Extensible parser selection by file extension. Add when building Python, JS/TS parsers.
- **Tree-sitter parsers:** Language-specific parsers for Python, JS/TS.
- **Cleanup command:** `code-index-mcp cleanup` to list and remove orphaned databases (project_path in metadata enables this).
- **Hybrid search:** Combine vector similarity with keyword search (SQLite FTS5) for better precision.
- **Query embedding cache:** Cache last N query embeddings for repeated searches.
- **Additional embedding models:** Allow users to choose different models via config.

## Documentation Plan

- [x] README.md: installation, Claude Code config, env vars, OpenAI setup, privacy notice, first-run model download note
- [x] CLAUDE.md: project conventions (Minitest, DHH style, file structure, testing approach)
- [x] Inline code comments: only for non-obvious decisions (e.g., why 50-line window, why 200ms budget, why sole-writer model)

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-06-code-index-mcp-brainstorm.md](docs/brainstorms/2026-03-06-code-index-mcp-brainstorm.md) — Key decisions carried forward: global gem distribution, Prism for Ruby + sliding window for rest, adapter pattern for embeddings (local + OpenAI), background indexing with smart reindex, usage metrics. Deferred from brainstorm to v2: config file, parser registry.

### Internal References

- Informant gem learnings: `/Users/d.lopez/Code/gems/informant/docs/solutions/code-review/rails-engine-comprehensive-review-learnings.md` — two-layer error handling, hot-path allocation avoidance, loud failures, real SQLite in tests, sole-writer threading model, connection pool with_connection pattern
- Version management pattern: `/Users/d.lopez/Code/gems/informant/docs/solutions/build-errors/manual-version-management-automation.md`

### External References

- [fast-mcp GitHub](https://github.com/yjacquin/fast-mcp) — tools docs, annotations, stdio transport
- [neighbor gem GitHub](https://github.com/ankane/neighbor) — sqlite-vec integration, has_neighbors API
- [informers gem GitHub](https://github.com/ankane/informers) — pipeline API, model caching
- [sqlite-vec documentation](https://alexgarcia.xyz/sqlite-vec/ruby.html) — vec0 virtual tables, distance metrics
- [Prism documentation](https://ruby.github.io/prism/) — AST visitor API

### Related Work

- [ruby-lsp](https://github.com/Shopify/ruby-lsp) — similar developer tool distribution pattern (global gem)
- [solargraph](https://github.com/castwide/solargraph) — similar developer tool with index-based search

### Review Findings Incorporated

Technical review on 2026-03-06 surfaced 14 findings (7 P1, 6 P2, 1 P3) from architecture, security, performance, simplicity, and agent-native reviewers. Key changes made:

- **Simplified v1 scope:** Removed config file and parser registry (YAGNI). Kept OpenAI adapter and metrics per user decision.
- **Sole-writer threading model:** Background worker owns all DB writes, eliminating contention
- **Security hardening:** Symlink traversal protection, array-form git commands, 0700 dir permissions
- **Agent experience:** Enriched tool descriptions, structured error responses, richer index state metadata
- **Performance:** Time-budget smart reindex (200ms), git diff caching, over-fetch for file_pattern, post-search dedup, batch indexer commits, verify sqlite-vec LIMIT pushdown
- **Architecture:** Extracted Runtime composition root, early FastMcp validation in Phase 1, graceful shutdown in Phase 2
