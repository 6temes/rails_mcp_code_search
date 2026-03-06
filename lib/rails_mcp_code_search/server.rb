require "mcp"

module RailsMcpCodeSearch
  class Server
    TOOLS = [
      Tools::ReindexTool,
      Tools::SearchTool,
      Tools::StatusTool
    ].freeze

    INSTRUCTIONS = <<~TEXT
      Use the code-search tools to find code by concept or behavior using natural language.
      This is semantic search — it finds code by meaning, not by exact string matching.

      When to use search vs Grep:
      - Use `search` when looking for concepts like "authentication", "payment processing", or "error handling"
      - Use `Grep` when looking for exact identifiers like a class name, method name, or string literal

      Workflow:
      1. The index builds automatically in the background when the server starts
      2. Use `status` to check if indexing is complete
      3. Use `search` with natural language queries to find relevant code
      4. Use `reindex` after major code changes, or with full=true to rebuild from scratch

      Tips:
      - Scores above 0.7 are strong matches, 0.5-0.7 are partial matches
      - Use `file_pattern` to narrow results (e.g. "app/models/**/*.rb")
      - Changed files are automatically re-indexed on each search
    TEXT

    def self.start(project_path: Dir.pwd, db_path: nil)
      runtime = Runtime.boot(project_path:, db_path:)

      server = ::MCP::Server.new(
        name: "rails-mcp-code-search",
        version: VERSION,
        instructions: INSTRUCTIONS,
        tools: TOOLS,
        server_context: { runtime: }
      )

      transport = ::MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end
  end
end
