require "mcp"
require "json"

module RailsMcpCodeSearch
  module Tools
    class BaseTool < ::MCP::Tool
      class << self
        private

        def runtime_for(server_context:)
          server_context[:runtime]
        end

        def text_response(data)
          text = data.is_a?(String) ? data : JSON.generate(data)
          ::MCP::Tool::Response.new([ { type: "text", text: } ])
        end

        def error_response(error:, message:, recoverable: false, suggested_action: nil)
          data = { error:, message:, recoverable:, suggested_action: }.compact
          ::MCP::Tool::Response.new([ { type: "text", text: JSON.generate(data) } ], error: true)
        end
      end
    end
  end
end
