require "test_helper"

module RailsMcpCodeSearch
  module Embeddings
    class LocalAdapterTest < Minitest::Test
      def setup
        @adapter = LocalAdapter.new
      end

      def test_dimensions
        assert_equal 384, @adapter.dimensions
      end

      def test_embed_single_text
        result = @adapter.embed("hello world")
        assert_equal 1, result.size
        assert_equal 384, result.first.size
      end

      def test_embed_batch
        result = @adapter.embed([ "hello", "world" ])
        assert_equal 2, result.size
        assert_equal 384, result[0].size
        assert_equal 384, result[1].size
      end

      def test_embeddings_are_normalized
        result = @adapter.embed("test sentence")
        magnitude = Math.sqrt(result.first.sum { _1**2 })
        assert_in_delta 1.0, magnitude, 0.001
      end
    end
  end
end
