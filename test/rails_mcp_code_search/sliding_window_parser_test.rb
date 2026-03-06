require "test_helper"

module RailsMcpCodeSearch
  class SlidingWindowParserTest < Minitest::Test
    def test_empty_source_returns_no_chunks
      assert_empty SlidingWindowParser.parse("")
    end

    def test_short_source_produces_single_chunk
      source = "line 1\nline 2\nline 3\n"
      chunks = SlidingWindowParser.parse(source)

      assert_equal 1, chunks.size
      assert_equal 1, chunks.first.line_start
      assert_equal 3, chunks.first.line_end
      assert_equal "window", chunks.first.chunk_type
      assert_nil chunks.first.qualified_name
    end

    def test_overlapping_windows
      source = (1..120).map { "line #{_1}\n" }.join
      chunks = SlidingWindowParser.parse(source)

      assert_equal 3, chunks.size
      assert_equal 1, chunks[0].line_start
      assert_equal 50, chunks[0].line_end
      assert_equal 41, chunks[1].line_start
      assert_equal 90, chunks[1].line_end
      assert_equal 81, chunks[2].line_start
      assert_equal 120, chunks[2].line_end
    end

    def test_caps_at_max_chunks
      source = (1..10_000).map { "line #{_1}\n" }.join
      chunks = SlidingWindowParser.parse(source)

      assert_operator chunks.size, :<=, SlidingWindowParser::MAX_CHUNKS
    end
  end
end
