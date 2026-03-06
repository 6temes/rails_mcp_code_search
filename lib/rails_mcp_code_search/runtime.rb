require "logger"

module RailsMcpCodeSearch
  class Runtime
    attr_reader :db_path, :embedding_adapter, :indexer, :worker, :logger, :project_path

    def self.boot(project_path: Dir.pwd, db_path: nil)
      new(project_path:, db_path:).tap(&:boot)
    end

    def initialize(project_path: Dir.pwd, db_path: nil)
      @project_path = project_path
      @db_path = db_path
      @logger = Logger.new($stderr, level: log_level)
      @logger.formatter = proc { |severity, _time, _progname, msg| "[rails-mcp-code-search] #{severity}: #{msg}\n" }
    end

    def boot
      @db_path = Database.setup(project_path: @project_path, db_path: @db_path)
      @embedding_adapter = build_adapter
      check_dimension_mismatch
      @indexer = Indexer.new(embedding_adapter: @embedding_adapter, project_path: @project_path, logger: @logger)
      @worker = BackgroundWorker.new(indexer: @indexer, logger: @logger)
      @worker.start
      setup_shutdown_hooks
      @logger.info "Booted for #{@project_path}"
    end

    def shutdown
      @worker&.stop
      @logger.info "Shut down"
    end

    private

    def build_adapter
      case ENV.fetch("RAILS_MCP_CODE_SEARCH_PROVIDER", "local")
      when "openai" then Embeddings::OpenaiAdapter.new
      else Embeddings::LocalAdapter.new
      end
    end

    def check_dimension_mismatch
      stored = Database::Metadata.get("embedding_dimensions")&.to_i
      return unless stored
      return if stored == @embedding_adapter.dimensions

      @logger.warn "Dimension mismatch (stored: #{stored}, active: #{@embedding_adapter.dimensions}). Triggering full reindex."
      Chunk.delete_all
      Database::Metadata.set "embedding_dimensions", @embedding_adapter.dimensions
    end

    def setup_shutdown_hooks
      at_exit { shutdown }
      trap("INT") { shutdown; exit }
      trap("TERM") { shutdown; exit }
    end

    def log_level
      ENV.fetch("RAILS_MCP_CODE_SEARCH_LOG_LEVEL", "info")
    end
  end
end
