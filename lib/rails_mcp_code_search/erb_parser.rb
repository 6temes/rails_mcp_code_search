require "herb"

module RailsMcpCodeSearch
  class ErbParser
    Result = RubyParser::Result
    MIN_LINES = 3
    MAX_CHUNKS = 30

    def self.parse(source, file_path: nil)
      new.parse(source, file_path:)
    end

    def parse(source, file_path: nil)
      result = Herb.parse(source)
      return SlidingWindowParser.parse(source, file_path:) unless result.success?

      visitor = Visitor.new(source)
      visitor.visit(result.value)
      chunks = deduplicate(visitor.chunks).first(MAX_CHUNKS)

      chunks.empty? ? SlidingWindowParser.parse(source, file_path:) : chunks
    rescue => _e
      SlidingWindowParser.parse(source, file_path:)
    end

    private

    def deduplicate(chunks)
      chunks.reject do |chunk|
        chunks.any? { _1 != chunk && _1.line_start <= chunk.line_start && _1.line_end >= chunk.line_end }
      end
    end

    class Visitor < Herb::Visitor
      attr_reader :chunks

      def initialize(source)
        super()
        @source = source
        @lines = source.lines
        @chunks = []
      end

      def visit_erb_block_node(node)
        add_chunk node, "erb_block"
        super
      end

      def visit_erb_if_node(node)
        add_chunk node, "erb_conditional"
        super
      end

      def visit_erb_unless_node(node)
        add_chunk node, "erb_conditional"
        super
      end

      def visit_erb_case_node(node)
        add_chunk node, "erb_conditional"
        super
      end

      def visit_html_element_node(node)
        add_chunk node, "html_element"
        super
      end

      private

      def add_chunk(node, type)
        line_start = node.location.start.line
        line_end = node.location.end.line
        return if (line_end - line_start + 1) < MIN_LINES

        content = @lines[(line_start - 1)..(line_end - 1)]&.join
        return if content.nil? || content.strip.empty?

        @chunks << Result.new(
          content:,
          line_start:,
          line_end:,
          chunk_type: type,
          qualified_name: nil
        )
      end
    end
  end
end
