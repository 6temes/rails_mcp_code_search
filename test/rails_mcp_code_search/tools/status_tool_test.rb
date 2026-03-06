require "test_helper"

module RailsMcpCodeSearch
  module Tools
    class StatusToolTest < Minitest::Test
      include TestHelper

      def setup
        @test_project_path = "/tmp/test_project"
        setup_test_db

        @worker = mock("worker")
        @worker.stubs(:state).returns(:idle)
        @worker.stubs(:progress).returns(1.0)
        @worker.stubs(:errors).returns([])

        adapter = Embeddings::LocalAdapter.new
        @runtime = mock("runtime")
        @runtime.stubs(:worker).returns(@worker)
        @runtime.stubs(:embedding_adapter).returns(adapter)
        @runtime.stubs(:project_path).returns("/tmp/test_project")
        @runtime.stubs(:db_path).returns(@test_db_path)

        @server_context = { runtime: @runtime }
      end

      def teardown
        teardown_test_db
      end

      def test_returns_empty_state_when_no_chunks
        response = StatusTool.call(server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal "empty", data["state"]
        assert_equal 0, data["chunk_count"]
      end

      def test_returns_ready_state_with_chunks
        Chunk.create!(
          file_path: "test.rb", line_start: 1, line_end: 5,
          chunk_type: "class", content: "class Foo; end",
          checksum: "abc", embedding: [ 0.1 ] * 384
        )

        response = StatusTool.call(server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal "ready", data["state"]
        assert_equal 1, data["chunk_count"]
        assert_equal 1, data["file_count"]
        assert_equal "local", data["embedding_provider"]
        assert_equal 384, data["embedding_dimensions"]
      end

      def test_returns_indexing_state
        @worker.stubs(:state).returns(:indexing)

        response = StatusTool.call(server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal "indexing", data["state"]
      end

      def test_includes_stats
        Database::Metadata.set "total_searches", "42"
        Database::Metadata.set "total_reindexes", "5"

        response = StatusTool.call(server_context: @server_context)
        data = JSON.parse(response.content.first[:text])

        assert_equal 42, data["stats"]["total_searches"]
        assert_equal 5, data["stats"]["total_reindexes"]
      end
    end
  end
end
