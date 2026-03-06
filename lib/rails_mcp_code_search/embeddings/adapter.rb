module RailsMcpCodeSearch
  module Embeddings
    class Adapter
      def embed(texts)
        raise NotImplementedError
      end

      def dimensions
        raise NotImplementedError
      end
    end
  end
end
