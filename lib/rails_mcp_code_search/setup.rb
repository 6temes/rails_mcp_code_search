require "json"
require "fileutils"

module RailsMcpCodeSearch
  module Setup
    WRAPPER_DIR = File.join(Dir.home, ".local", "bin")
    WRAPPER_PATH = File.join(WRAPPER_DIR, "rails-mcp-code-search")

    class << self
      def run
        puts "Setting up rails-mcp-code-search...\n\n"

        create_wrapper
        configure_claude_code

        puts "\nDone! Restart Claude Code in this project to start using semantic search."
      end

      private

      def create_wrapper
        FileUtils.mkdir_p WRAPPER_DIR

        init_command = detect_ruby_manager
        wrapper = <<~BASH
          #!/bin/bash
          #{init_command}
          exec rails-mcp-code-search "$@"
        BASH

        File.write WRAPPER_PATH, wrapper
        File.chmod 0o755, WRAPPER_PATH
        puts "Created wrapper script: #{WRAPPER_PATH}"
      end

      def detect_ruby_manager
        if rbenv_path = find_executable("rbenv")
          "eval \"$(#{rbenv_path} init - bash)\""
        elsif asdf_path = find_asdf
          ". #{asdf_path}"
        elsif chruby_path = find_chruby
          "source #{chruby_path}\nchruby ruby"
        else
          "# System Ruby — no version manager detected"
        end
      end

      def find_executable(name)
        [
          "/opt/homebrew/bin/#{name}",
          "/usr/local/bin/#{name}",
          File.join(Dir.home, ".#{name}", "bin", name)
        ].find { File.executable?(_1) }
      end

      def find_asdf
        path = File.join(Dir.home, ".asdf", "asdf.sh")
        path if File.exist?(path)
      end

      def find_chruby
        [
          "/opt/homebrew/share/chruby/chruby.sh",
          "/usr/local/share/chruby/chruby.sh"
        ].find { File.exist?(_1) }
      end

      def configure_claude_code
        mcp_config_path = File.join(Dir.pwd, ".mcp.json")

        config = if File.exist?(mcp_config_path)
          JSON.parse File.read(mcp_config_path)
        else
          {}
        end

        config["mcpServers"] ||= {}
        config["mcpServers"]["code-search"] = { "command" => WRAPPER_PATH }

        File.write mcp_config_path, JSON.pretty_generate(config) + "\n"
        puts "Configured Claude Code: #{mcp_config_path}"
      end
    end
  end
end
