require "minitest/autorun"
require "mocha/minitest"
require "tmpdir"
require "fileutils"
require "securerandom"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rails_mcp_code_search"


module TestHelper
  def setup_test_db
    @test_db_path = File.join(Dir.tmpdir, "rails_mcp_code_search_test_#{SecureRandom.hex(8)}.db")
    RailsMcpCodeSearch::Database.setup(project_path: @test_project_path || Dir.pwd, db_path: @test_db_path)
  end

  def teardown_test_db
    ActiveRecord::Base.connection_pool.disconnect!
    File.delete(@test_db_path) if @test_db_path && File.exist?(@test_db_path)
  end

  def setup_test_project
    @test_project_path = Dir.mktmpdir("rails_mcp_code_search_test")
    system("git", "init", @test_project_path, out: File::NULL, err: File::NULL)
    @test_project_path
  end

  def teardown_test_project
    FileUtils.rm_rf(@test_project_path) if @test_project_path
  end

  def write_test_file(relative_path, content)
    full_path = File.join(@test_project_path, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    system("git", "-C", @test_project_path, "add", relative_path, out: File::NULL, err: File::NULL)
    full_path
  end
end
