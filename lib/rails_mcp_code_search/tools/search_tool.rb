module RailsMcpCodeSearch
  module Tools
    class SearchTool < BaseTool
      tool_name "search"
      description "Search the codebase using semantic similarity. Use this when you need to find " \
                  "code by concept or behavior (e.g., 'authentication logic', 'payment processing') " \
                  "rather than by exact identifier. For exact string matches, prefer Grep. " \
                  "Returns code chunks ranked by cosine similarity. " \
                  "Scores above 0.7 are typically strong matches, 0.5-0.7 are partial matches."

      input_schema(
        properties: {
          query: { type: "string", description: "Search query (natural language or code)" },
          limit: { type: "integer", description: "Max results (default 10)" },
          file_pattern: { type: "string", description: "Glob pattern to filter results by file path (e.g. 'app/models/**/*.rb'). Applied after similarity search." }
        },
        required: %w[query]
      )

      annotations(
        title: "Search Code",
        read_only_hint: true,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      def self.call(query:, server_context:, limit: nil, file_pattern: nil)
        runtime = runtime_for(server_context:)
        limit = (limit || 10).clamp(1, 50)

        if Chunk.count == 0
          worker_state = runtime.worker.state
          if worker_state == :indexing
            return error_response(error: "indexing_in_progress", message: "Index is still building. Try again in a moment.", recoverable: true, suggested_action: "status")
          else
            return error_response(error: "index_empty", message: "No files indexed yet. Call reindex first.", recoverable: true, suggested_action: "reindex")
          end
        end

        # Smart reindex: enqueue changed files and wait briefly
        trigger_smart_reindex(runtime)

        # Generate query embedding
        query_vector = runtime.embedding_adapter.embed([ query ]).first

        # KNN search — over-fetch if filtering by file pattern
        fetch_limit = file_pattern ? limit * 5 : limit
        raw_results = Chunk.nearest_neighbors(:embedding, query_vector, distance: "cosine").first(fetch_limit)

        # Filter by file pattern
        filtered_out = 0
        if file_pattern
          before_count = raw_results.size
          raw_results = raw_results.select { File.fnmatch?(file_pattern, _1.file_path, File::FNM_PATHNAME) }
          filtered_out = before_count - raw_results.size
        end

        # Dedup overlapping results from same file
        results = dedup_overlapping(raw_results)
        results = results.first(limit)

        # Track metrics
        runtime.worker.enqueue_hit_counts(results.map(&:id))
        runtime.worker.increment_search_count

        stale = runtime.worker.state == :indexing

        text_response({
          results: results.map { format_result(_1) },
          metadata: {
            query:,
            limit:,
            count: results.size,
            has_more: raw_results.size > limit,
            index_state: runtime.worker.state.to_s,
            index_completeness: runtime.worker.state == :idle ? 1.0 : runtime.worker.progress,
            results_may_be_stale: stale,
            total_indexed_chunks: Chunk.count,
            filtered_out_count: filtered_out
          }
        })
      rescue => e
        error_response(error: "search_error", message: e.message, recoverable: true)
      end

      class << self
        private

        def trigger_smart_reindex(runtime)
          changed = runtime.indexer.changed_files
          return if changed.empty?

          runtime.worker.enqueue(:index_files, payload: changed)
          runtime.worker.wait_for_reindex(timeout: 0.2)
        end

        def dedup_overlapping(results)
          seen = {}
          results.reject do |r|
            key = r.file_path
            if seen[key]
              overlap = seen[key].any? do |prev|
                r.line_start <= prev.line_end && r.line_end >= prev.line_start
              end
              overlap
            else
              seen[key] = [ r ]
              false
            end.tap { seen[key] = (seen[key] || []) + [ r ] unless _1 }
          end
        end

        def format_result(chunk)
          {
            file_path: chunk.file_path,
            line_start: chunk.line_start,
            line_end: chunk.line_end,
            chunk_type: chunk.chunk_type,
            qualified_name: chunk.qualified_name,
            content: chunk.content,
            similarity: (1.0 - chunk.neighbor_distance).round(4)
          }
        end
      end
    end
  end
end
