require "test_helper"

module RailsMcpCodeSearch
  module Tools
    class ReindexToolTest < Minitest::Test
      include TestHelper

      def setup
        setup_test_project
        setup_test_db

        adapter = Embeddings::LocalAdapter.new
        @indexer = Indexer.new(embedding_adapter: adapter, project_path: @test_project_path)

        @worker = mock("worker")
        @worker.stubs(:enqueue)
        @worker.stubs(:increment_reindex_count)

        @runtime = mock("runtime")
        @runtime.stubs(:worker).returns(@worker)
        @runtime.stubs(:indexer).returns(@indexer)

        @server_context = { runtime: @runtime }
      end

      def teardown
        teardown_test_db
        teardown_test_project
      end

      def test_full_reindex
        @worker.expects(:enqueue).with(:full_index)

        response = ReindexTool.call(full: true, server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal "reindex_started", data["status"]
        assert_equal "full", data["mode"]
      end

      def test_incremental_with_no_changes
        response = ReindexTool.call(server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal "no_changes", data["status"]
        assert_equal "incremental", data["mode"]
      end
    end
  end
end
