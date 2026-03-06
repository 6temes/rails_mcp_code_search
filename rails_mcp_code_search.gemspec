require_relative "lib/rails_mcp_code_search/version"

Gem::Specification.new do |spec|
  spec.name = "rails_mcp_code_search"
  spec.version = RailsMcpCodeSearch::VERSION
  spec.authors = [ "Daniel Lopez Prat" ]
  spec.email = [ "daniel@6temes.cat" ]
  spec.homepage = "https://github.com/6temes/rails_mcp_code_search"
  spec.summary = "Semantic codebase search for Claude Code via MCP"
  spec.description = "MCP server that indexes codebases using AST-aware chunking and vector embeddings, " \
                     "providing semantic search for Claude Code and other MCP clients."
  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/6temes/rails_mcp_code_search/issues",
    "changelog_uri" => "https://github.com/6temes/rails_mcp_code_search/releases",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/6temes/rails_mcp_code_search"
  }

  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,exe}/**/*", "LICENSE", "Rakefile", "README.md"]
  end

  spec.bindir = "exe"
  spec.executables = [ "rails-mcp-code-search" ]

  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "herb", "~> 0.8"
  spec.add_dependency "informers", "~> 1.2"
  spec.add_dependency "mcp", ">= 0.7", "< 2"
  spec.add_dependency "neighbor", "~> 0.6"
  spec.add_dependency "ruby-openai", "~> 8.0"
  spec.add_dependency "sqlite-vec", "~> 0.1"
  spec.add_dependency "sqlite3", "~> 2.0"
end
