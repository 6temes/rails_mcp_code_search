require "informers"

module RailsMcpCodeSearch
  module Embeddings
    class LocalAdapter < Adapter
      DIMENSIONS = 384
      MODEL = "sentence-transformers/all-MiniLM-L6-v2"

      def initialize
        @mutex = Mutex.new
      end

      def embed(texts)
        texts = Array(texts)
        pipeline.call(texts)
      end

      def dimensions = DIMENSIONS

      private

      def pipeline
        @mutex.synchronize do
          @_pipeline ||= Informers.pipeline("embedding", MODEL)
        end
      end
    end
  end
end
