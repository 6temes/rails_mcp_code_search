require "test_helper"

module RailsMcpCodeSearch
  module Tools
    class SearchToolTest < Minitest::Test
      include TestHelper

      def setup
        setup_test_project
        setup_test_db

        write_test_file "user.rb", <<~RUBY
          class User
            def authenticate(password)
              BCrypt::Password.new(password_digest) == password
            end
          end
        RUBY

        adapter = Embeddings::LocalAdapter.new
        indexer = Indexer.new(embedding_adapter: adapter, project_path: @test_project_path)
        indexer.index_all

        @worker = mock("worker")
        @worker.stubs(:state).returns(:idle)
        @worker.stubs(:progress).returns(1.0)
        @worker.stubs(:enqueue_hit_counts)
        @worker.stubs(:increment_search_count)
        @worker.stubs(:enqueue)
        @worker.stubs(:wait_for_reindex).returns(true)

        @runtime = mock("runtime")
        @runtime.stubs(:embedding_adapter).returns(adapter)
        @runtime.stubs(:indexer).returns(indexer)
        @runtime.stubs(:worker).returns(@worker)

        @server_context = { runtime: @runtime }
      end

      def teardown
        teardown_test_db
        teardown_test_project
      end

      def test_search_returns_results
        response = SearchTool.call(query: "user authentication", server_context: @server_context)

        refute response.error?
        data = JSON.parse(response.content.first[:text])
        assert data["results"].any?
        assert data["metadata"]["count"] > 0
      end

      def test_search_returns_similarity_scores
        response = SearchTool.call(query: "authenticate", server_context: @server_context)

        data = JSON.parse(response.content.first[:text])
        result = data["results"].first
        assert result["similarity"].is_a?(Numeric)
        assert result["file_path"]
        assert result["content"]
      end

      def test_search_empty_index_returns_error
        Chunk.delete_all

        response = SearchTool.call(query: "anything", server_context: @server_context)

        assert response.error?
        data = JSON.parse(response.content.first[:text])
        assert_equal "index_empty", data["error"]
        assert data["recoverable"]
      end

      def test_search_with_file_pattern
        response = SearchTool.call(
          query: "user", file_pattern: "*.rb",
          server_context: @server_context
        )

        data = JSON.parse(response.content.first[:text])
        data["results"].each do |r|
          assert r["file_path"].end_with?(".rb")
        end
      end
    end
  end
end
