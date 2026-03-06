module RailsMcpCodeSearch
  module Tools
    class ReindexTool < BaseTool
      tool_name "reindex"
      description "Trigger codebase reindex. Use full=true to rebuild the entire index. " \
                  "Returns immediately — use the status tool to check progress."

      input_schema(
        properties: {
          full: { type: "boolean", description: "Full reindex (default: incremental)" }
        }
      )

      annotations(
        title: "Reindex Code",
        read_only_hint: false,
        destructive_hint: false,
        idempotent_hint: true,
        open_world_hint: false
      )

      def self.call(server_context:, full: nil)
        runtime = runtime_for(server_context:)
        full = full == true

        if full
          runtime.worker.enqueue(:full_index)
          runtime.worker.increment_reindex_count
          estimated = runtime.indexer.discover_files.size rescue 0

          text_response({
            status: "reindex_started",
            mode: "full",
            estimated_files: estimated
          })
        else
          changed = runtime.indexer.changed_files
          if changed.empty?
            text_response({ status: "no_changes", mode: "incremental", changed_files: 0 })
          else
            runtime.worker.enqueue(:index_files, payload: changed)
            runtime.worker.increment_reindex_count
            text_response({ status: "reindex_started", mode: "incremental", changed_files: changed.size })
          end
        end
      rescue => e
        error_response(error: "reindex_error", message: e.message, recoverable: true)
      end
    end
  end
end
