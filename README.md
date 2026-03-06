<div align="center">

  <h1 style="margin-top: 10px;">rails_mcp_code_search</h1>

  <h3>Semantic codebase search for Claude Code via MCP</h3>

  <p>Think Cursor's codebase indexing, but for Claude Code.</p>

  <div align="center">
    <a href="https://github.com/6temes/rails_mcp_code_search/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"/></a>
    <a href="https://rubygems.org/gems/rails_mcp_code_search"><img alt="Gem Version" src="https://img.shields.io/gem/v/rails_mcp_code_search"/></a>
    <a href="https://github.com/6temes/rails_mcp_code_search/actions"><img alt="CI" src="https://github.com/6temes/rails_mcp_code_search/actions/workflows/ci.yml/badge.svg"/></a>
  </div>

  <p>
    <a href="#how-it-works">How It Works</a> ◆
    <a href="#quick-start">Quick Start</a> ◆
    <a href="#tools">Tools</a> ◆
    <a href="#configuration">Configuration</a> ◆
    <a href="#architecture">Architecture</a>
  </p>

</div>

---

## How It Works

- **Ruby files** — Parsed with [Prism](https://ruby.github.io/prism/) into classes, modules, and methods
- **ERB templates** — Parsed with [Herb](https://github.com/marcoroth/herb) into blocks, conditionals, and HTML elements
- **Other files** (JS, TS, YAML, Markdown) — Sliding window chunking
- **Embeddings** — Generated locally with [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) (384 dimensions, zero config)
- **Vector search** — SQLite + [sqlite-vec](https://alexgarcia.xyz/sqlite-vec/) for cosine similarity
- **Background indexing** — Starts automatically, search is available immediately

## Quick Start

```sh
gem install rails_mcp_code_search
rails-mcp-code-search --setup
```

Requires Ruby 4.0+. The setup command creates a version-independent wrapper script and configures Claude Code automatically. The first search downloads the embedding model (~80 MB) to `~/.cache/informers/`.

## Tools

### search

Search the codebase by concept or behavior using natural language.

```text
query: "user authentication logic"
limit: 10
file_pattern: "app/models/**/*.rb"
```

Returns ranked results with file path, line range, similarity score, and code content. On each search, changed files are automatically re-indexed with a 200ms time budget.

### reindex

Trigger a manual reindex. Returns immediately — runs in the background.

```text
full: true    # Rebuild entire index
full: false   # Incremental (default, only changed files)
```

### status

Check index health, chunk count, embedding provider, and search stats.

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `RAILS_MCP_CODE_SEARCH_PROVIDER` | `local` | Embedding provider: `local` or `openai` |
| `RAILS_MCP_CODE_SEARCH_DB_PATH` | auto | Override database file path |
| `RAILS_MCP_CODE_SEARCH_LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `RAILS_MCP_CODE_SEARCH_OPENAI_API_KEY` | — | Required when provider is `openai` |

### OpenAI Provider

For faster indexing or higher-dimensional embeddings, use OpenAI's `text-embedding-3-small` (1536 dimensions):

```sh
export RAILS_MCP_CODE_SEARCH_PROVIDER=openai
export RAILS_MCP_CODE_SEARCH_OPENAI_API_KEY=sk-...
```

| | Local (default) | OpenAI |
|---|---|---|
| Dimensions | 384 | 1536 |
| Speed | ~5 min / 1000 files | ~15s / 1000 files |
| Cost | Free | Per-token API cost |
| Privacy | Everything stays local | Code sent to OpenAI |
| Setup | Zero config | Requires API key |

Switching providers triggers a full reindex automatically.

> **Privacy notice:** When using the OpenAI provider, source code chunks from your repository are sent to OpenAI's embedding API. The local provider (default) keeps everything on your machine.

### Supported File Types

`*.rb` `*.erb` `*.js` `*.ts` `*.yml` `*.yaml` `*.md`

Excluded: `vendor/` `node_modules/` `tmp/` `log/`

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│                    Claude Code                          │
│                  (MCP Client)                           │
└──────────────────────┬──────────────────────────────────┘
                       │ stdio
                       ▼
┌─────────────────────────────────────────────────────────┐
│  MCP Server (search, reindex, status)                   │
└──────────────────────┬──────────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
┌──────────────────┐     ┌──────────────────┐
│  Background       │     │  Embedding        │
│  Worker           │     │  Adapter          │
│  (sole writer)    │     │  (local / openai) │
└────────┬─────────┘     └────────┬─────────┘
         │                        │
         ▼                        ▼
┌─────────────────────────────────────────────┐
│  SQLite + sqlite-vec                        │
│  (WAL mode, per-project DB)                 │
│  ~/.local/share/rails-mcp-code-search/      │
└─────────────────────────────────────────────┘
```

### Parsers

| File Type | Parser | Chunk Types |
|-----------|--------|-------------|
| `*.rb` | Prism AST | `class`, `module`, `method` |
| `*.erb` | Herb AST | `erb_block`, `erb_conditional`, `html_element` |
| Everything else | Sliding window | `window` (50 lines, 10 overlap) |

### Key Design Decisions

- **Standalone ActiveRecord** — No Rails runtime dependency, just SQLite
- **Single writer thread** — All DB mutations go through the background worker
- **Smart reindex** — Changed files (via `git diff`) are re-indexed before each search
- **Per-project database** — SHA256 of the project path, stored in `~/.local/share/`
- **Prism + Herb AST** — Semantic chunking produces better search results than naive line splitting

## License

MIT

---

<div align="center">
  <p>Made in Tokyo with ❤️ and 🤖</p>
</div>
