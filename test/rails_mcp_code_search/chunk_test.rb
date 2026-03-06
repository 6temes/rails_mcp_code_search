require "test_helper"

module RailsMcpCodeSearch
  class ChunkTest < Minitest::Test
    include TestHelper

    def setup
      @test_project_path = "/tmp/test_project"
      setup_test_db
    end

    def teardown
      teardown_test_db
    end

    def test_create_chunk_with_embedding
      chunk = Chunk.create!(
        file_path: "test.rb", line_start: 1, line_end: 10,
        chunk_type: "method", qualified_name: "Foo#bar",
        content: "def bar; end", checksum: "abc123",
        embedding: [ 0.1 ] * 384
      )

      assert chunk.persisted?
      assert_equal "test.rb", chunk.file_path
      assert_equal 0, chunk.hit_count
    end

    def test_nearest_neighbors_search
      Chunk.create!(
        file_path: "a.rb", line_start: 1, line_end: 5,
        chunk_type: "method", content: "def hello; end",
        checksum: "a1", embedding: [ 1.0 ] + [ 0.0 ] * 383
      )
      Chunk.create!(
        file_path: "b.rb", line_start: 1, line_end: 5,
        chunk_type: "method", content: "def world; end",
        checksum: "b1", embedding: [ 0.0, 1.0 ] + [ 0.0 ] * 382
      )

      query = [ 1.0 ] + [ 0.0 ] * 383
      results = Chunk.nearest_neighbors(:embedding, query, distance: "cosine").first(2)

      assert_equal 2, results.size
      assert_equal "a.rb", results.first.file_path
    end
  end
end
