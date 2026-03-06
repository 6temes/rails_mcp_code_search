require "test_helper"

module RailsMcpCodeSearch
  class DatabaseTest < Minitest::Test
    include TestHelper

    def setup
      @test_project_path = "/tmp/test_project"
      setup_test_db
    end

    def teardown
      teardown_test_db
    end

    def test_creates_chunks_table
      assert ActiveRecord::Base.connection.table_exists?(:chunks)
    end

    def test_creates_metadata_table
      assert ActiveRecord::Base.connection.table_exists?(:metadata)
    end

    def test_wal_mode
      result = ActiveRecord::Base.connection.execute("PRAGMA journal_mode").first
      assert_equal "wal", result["journal_mode"]
    end

    def test_stores_project_path_in_metadata
      assert_equal "/tmp/test_project", Database::Metadata.get("project_path")
    end

    def test_db_path_uses_sha256_of_project_path
      path = Database.db_path_for("/some/project")
      digest = Digest::SHA256.hexdigest("/some/project")
      assert path.end_with?("#{digest}.db")
    end

    def test_metadata_set_and_get
      Database::Metadata.set "test_key", "test_value"
      assert_equal "test_value", Database::Metadata.get("test_key")
    end

    def test_metadata_upsert
      Database::Metadata.set "key", "value1"
      Database::Metadata.set "key", "value2"
      assert_equal "value2", Database::Metadata.get("key")
    end

    def test_metadata_get_returns_nil_for_missing_key
      assert_nil Database::Metadata.get("nonexistent")
    end
  end
end
