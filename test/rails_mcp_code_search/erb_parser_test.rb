require "test_helper"

module RailsMcpCodeSearch
  class ErbParserTest < Minitest::Test
    def test_parses_erb_block
      source = <<~ERB
        <% @users.each do |user| %>
          <div class="user">
            <p><%= user.name %></p>
          </div>
        <% end %>
      ERB

      chunks = ErbParser.parse(source)
      block = chunks.find { _1.chunk_type == "erb_block" }

      assert block, "Expected an erb_block chunk"
      assert_includes block.content, "@users.each"
    end

    def test_parses_erb_conditional
      source = <<~ERB
        <% if @user.admin? %>
          <div class="admin-panel">Admin</div>
        <% end %>
      ERB

      chunks = ErbParser.parse(source)
      conditional = chunks.find { _1.chunk_type == "erb_conditional" }

      assert conditional, "Expected an erb_conditional chunk"
      assert_includes conditional.content, "admin?"
    end

    def test_parses_multiline_html_element
      source = <<~ERB
        <div class="card">
          <h2>Title</h2>
          <p>Content</p>
        </div>
      ERB

      chunks = ErbParser.parse(source)
      element = chunks.find { _1.chunk_type == "html_element" }

      assert element, "Expected an html_element chunk"
      assert_includes element.content, "card"
      assert_equal 1, element.line_start
      assert_equal 4, element.line_end
    end

    def test_skips_chunks_shorter_than_three_lines
      source = <<~ERB
        <p>Short</p>
        <% if true %>
          <span>Two lines</span>
        <% end %>
      ERB

      chunks = ErbParser.parse(source)
      # Both the <p> (1 line) and the if block (3 lines) are too small or at boundary
      # Single-line elements and 2-line elements should be skipped
      chunks.each do |chunk|
        next if chunk.chunk_type == "window"
        assert chunk.line_end - chunk.line_start + 1 >= 3, "Chunk should span at least 3 lines"
      end
    end

    def test_falls_back_to_sliding_window_on_empty_ast
      source = "just plain text without any erb or html"

      chunks = ErbParser.parse(source)

      assert chunks.any?
      assert_equal "window", chunks.first.chunk_type
    end

    def test_deduplicates_nested_chunks
      source = <<~ERB
        <div class="wrapper">
          <% @users.each do |user| %>
            <div class="user-card">
              <h2><%= user.name %></h2>
              <p><%= user.email %></p>
            </div>
          <% end %>
        </div>
      ERB

      chunks = ErbParser.parse(source)

      # The inner div (lines 3-6) is inside the erb_block (lines 2-7),
      # which is inside the outer div (lines 1-8). Dedup should remove
      # chunks fully contained by a parent.
      assert chunks.size <= 3, "Expected deduplication to remove nested chunks, got #{chunks.size}"
    end

    def test_caps_chunks_per_file
      # Generate a large ERB file with many blocks
      blocks = (1..50).map do |i|
        <<~ERB
          <% @items_#{i}.each do |item| %>
            <div class="item">
              <p><%= item.name %></p>
            </div>
          <% end %>
        ERB
      end
      source = blocks.join("\n")

      chunks = ErbParser.parse(source)

      assert chunks.size <= ErbParser::MAX_CHUNKS, "Expected at most #{ErbParser::MAX_CHUNKS} chunks, got #{chunks.size}"
    end

    def test_parses_complex_rails_template
      source = <<~ERB
        <div class="users-index">
          <h1>Users</h1>

          <%= form_with url: users_path, method: :get do |form| %>
            <%= form.text_field :query %>
            <%= form.submit "Search" %>
          <% end %>

          <% @users.each do |user| %>
            <div class="user-card">
              <h2><%= user.name %></h2>
              <p><%= user.email %></p>
              <% if user.admin? %>
                <span class="badge">Admin</span>
              <% end %>
            </div>
          <% end %>
        </div>
      ERB

      chunks = ErbParser.parse(source)
      types = chunks.map(&:chunk_type).uniq.sort

      # Outer div contains everything, so nested blocks are deduped
      assert_includes types, "html_element"
      assert chunks.any? { _1.content.include?("form_with") || _1.content.include?("@users.each") }
    end

    def test_uses_result_data_struct
      source = <<~ERB
        <% @items.each do |item| %>
          <div class="item">
            <p><%= item.name %></p>
          </div>
        <% end %>
      ERB

      chunks = ErbParser.parse(source)

      assert chunks.all? { _1.is_a?(RubyParser::Result) }
    end
  end
end
