require_relative "rails_mcp_code_search/version"

module RailsMcpCodeSearch
  autoload :BackgroundWorker, "rails_mcp_code_search/background_worker"
  autoload :Chunk, "rails_mcp_code_search/chunk"
  autoload :Database, "rails_mcp_code_search/database"
  autoload :ErbParser, "rails_mcp_code_search/erb_parser"
  autoload :Indexer, "rails_mcp_code_search/indexer"
  autoload :Runtime, "rails_mcp_code_search/runtime"
  autoload :RubyParser, "rails_mcp_code_search/ruby_parser"
  autoload :Server, "rails_mcp_code_search/server"
  autoload :SlidingWindowParser, "rails_mcp_code_search/sliding_window_parser"

  module Embeddings
    autoload :Adapter, "rails_mcp_code_search/embeddings/adapter"
    autoload :LocalAdapter, "rails_mcp_code_search/embeddings/local_adapter"
    autoload :OpenaiAdapter, "rails_mcp_code_search/embeddings/openai_adapter"
  end

  module Tools
    autoload :BaseTool, "rails_mcp_code_search/tools/base_tool"
    autoload :ReindexTool, "rails_mcp_code_search/tools/reindex_tool"
    autoload :SearchTool, "rails_mcp_code_search/tools/search_tool"
    autoload :StatusTool, "rails_mcp_code_search/tools/status_tool"
  end
end
