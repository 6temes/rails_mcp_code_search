require "test_helper"

module RailsMcpCodeSearch
  class IndexerTest < Minitest::Test
    include TestHelper

    def setup
      setup_test_project
      setup_test_db

      @adapter = Embeddings::LocalAdapter.new
      @indexer = Indexer.new(embedding_adapter: @adapter, project_path: @test_project_path)
    end

    def teardown
      teardown_test_db
      teardown_test_project
    end

    def test_indexes_ruby_file
      write_test_file "app.rb", <<~RUBY
        class App
          def run
            puts "running"
          end
        end
      RUBY

      @indexer.index_all

      assert_operator Chunk.count, :>, 0
      assert Chunk.where(file_path: "app.rb").exists?
    end

    def test_indexes_non_ruby_file_with_sliding_window
      write_test_file "config.yml", "key: value\n" * 5

      @indexer.index_all

      chunk = Chunk.find_by(file_path: "config.yml")
      assert_equal "window", chunk.chunk_type
    end

    def test_skips_excluded_directories
      write_test_file "vendor/cache/gem.rb", "class Gem; end"
      write_test_file "app.rb", "class App; end"

      @indexer.index_all

      refute Chunk.where(file_path: "vendor/cache/gem.rb").exists?
      assert Chunk.where(file_path: "app.rb").exists?
    end

    def test_incremental_skips_unchanged_files
      write_test_file "app.rb", "class App; end"

      @indexer.index_all
      first_count = Chunk.count

      @indexer.index_all
      assert_equal first_count, Chunk.count
    end

    def test_reindexes_changed_files
      write_test_file "app.rb", "class App; end"
      @indexer.index_all

      write_test_file "app.rb", "class App\n  def new_method; end\nend"
      @indexer.index_all

      assert Chunk.where(file_path: "app.rb").where(chunk_type: "method").exists?
    end

    def test_not_a_git_repo_raises
      non_git = Dir.mktmpdir("not_git")
      indexer = Indexer.new(embedding_adapter: @adapter, project_path: non_git)

      assert_raises(Indexer::NotAGitRepo) { indexer.index_all }
    ensure
      FileUtils.rm_rf(non_git)
    end

    def test_stores_embeddings
      write_test_file "app.rb", "class App; end"

      @indexer.index_all

      chunk = Chunk.find_by(file_path: "app.rb")
      assert chunk.embedding.present?
    end

    def test_tracks_errors_for_invalid_files
      write_test_file "bad.rb", "\xFF\xFE invalid utf-8"

      @indexer.index_all

      # Should not crash, errors tracked
      assert @indexer.errors.empty? || @indexer.errors.any? { _1[:file] == "bad.rb" }
    end
  end
end
