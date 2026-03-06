require "openai"

module RailsMcpCodeSearch
  module Embeddings
    class OpenaiAdapter < Adapter
      DIMENSIONS = 1536
      MODEL = "text-embedding-3-small"
      MAX_RETRIES = 3
      MAX_CHARS = 15_000

      ApiKeyError = Class.new(StandardError)

      def initialize
        api_key = ENV["RAILS_MCP_CODE_SEARCH_OPENAI_API_KEY"]
        raise ApiKeyError, "RAILS_MCP_CODE_SEARCH_OPENAI_API_KEY environment variable is required for OpenAI provider" unless api_key

        @client = OpenAI::Client.new(access_token: api_key)
        @warned = false
      end

      def embed(texts)
        texts = Array(texts).map { truncate(_1) }
        warn_once

        retries = 0
        begin
          response = @client.embeddings(parameters: { model: MODEL, input: texts })
          response.dig("data").sort_by { _1["index"] }.map { _1["embedding"] }
        rescue Faraday::TooManyRequestsError
          retries += 1
          raise if retries > MAX_RETRIES
          sleep(2**retries)
          retry
        rescue => e
          raise sanitize_error(e)
        end
      end

      def dimensions = DIMENSIONS

      private

      def warn_once
        return if @warned
        @warned = true
        $stderr.puts "[rails-mcp-code-search] WARNING: Source code from this repository will be sent to OpenAI's embedding API."
      end

      def truncate(text)
        text.size > MAX_CHARS ? text[0, MAX_CHARS] : text
      end

      def sanitize_error(error)
        message = error.message.gsub(/sk-[A-Za-z0-9_-]+/, "[REDACTED]")
        StandardError.new(message)
      end
    end
  end
end
