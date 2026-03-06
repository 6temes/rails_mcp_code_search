module RailsMcpCodeSearch
  module Tools
    class StatusTool < BaseTool
      tool_name "status"
      description "Show index health and readiness. Use to check if indexing is complete " \
                  "before searching, or to diagnose issues."

      input_schema(properties: {})

      annotations(
        title: "Index Status",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      def self.call(server_context:)
        runtime = runtime_for(server_context:)
        worker = runtime.worker

        chunk_count = Chunk.count
        file_count = Chunk.distinct.pluck(:file_path).size

        state = if worker.state == :error
          "error"
        elsif worker.state == :indexing
          "indexing"
        elsif chunk_count == 0
          "empty"
        else
          "ready"
        end

        db_size = File.size(runtime.db_path) rescue 0

        top_chunks = Chunk.where("hit_count > 0").order(hit_count: :desc).limit(5).map do |c|
          { file_path: c.file_path, qualified_name: c.qualified_name, hit_count: c.hit_count }
        end

        text_response({
          state:,
          chunk_count:,
          file_count:,
          db_size_bytes: db_size,
          index_completeness: worker.state == :idle ? 1.0 : worker.progress,
          embedding_provider: runtime.embedding_adapter.class.name.split("::").last.sub("Adapter", "").downcase,
          embedding_dimensions: runtime.embedding_adapter.dimensions,
          project_path: runtime.project_path,
          indexing_errors: worker.errors.first(10),
          stats: {
            total_searches: Database::Metadata.get("total_searches").to_i,
            total_reindexes: Database::Metadata.get("total_reindexes").to_i,
            last_search_at: Database::Metadata.get("last_search_at"),
            last_reindex_at: Database::Metadata.get("last_reindex_at")
          },
          top_chunks_by_hits: top_chunks
        })
      rescue => e
        error_response(error: "status_error", message: e.message, recoverable: true)
      end
    end
  end
end
