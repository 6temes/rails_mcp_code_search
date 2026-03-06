require "mcp"

module RailsMcpCodeSearch
  class Server
    TOOLS = [
      Tools::ReindexTool,
      Tools::SearchTool,
      Tools::StatusTool
    ].freeze

    def self.start(project_path: Dir.pwd, db_path: nil)
      runtime = Runtime.boot(project_path:, db_path:)

      server = ::MCP::Server.new(
        name: "rails-mcp-code-search",
        version: VERSION,
        tools: TOOLS,
        server_context: { runtime: }
      )

      transport = ::MCP::Server::Transports::StdioTransport.new(server)
      transport.open
    end
  end
end
