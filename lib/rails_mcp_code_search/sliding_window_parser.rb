module RailsMcpCodeSearch
  class SlidingWindowParser
    WINDOW_SIZE = 50
    OVERLAP = 10
    MAX_CHUNKS = 200

    Result = RubyParser::Result

    def self.parse(source, file_path: nil)
      new.parse(source, file_path:)
    end

    def parse(source, file_path: nil)
      lines = source.lines
      return [] if lines.empty?

      chunks = []
      step = WINDOW_SIZE - OVERLAP
      offset = 0

      while offset < lines.size && chunks.size < MAX_CHUNKS
        window_end = [ offset + WINDOW_SIZE, lines.size ].min
        content = lines[offset...window_end].join

        chunks << Result.new(
          content:,
          line_start: offset + 1,
          line_end: window_end,
          chunk_type: "window",
          qualified_name: nil
        )

        offset += step
      end

      chunks
    end
  end
end
