require "test_helper"

module RailsMcpCodeSearch
  class RubyParserTest < Minitest::Test
    def test_parses_class_with_methods
      source = <<~RUBY
        class User
          def initialize(name)
            @name = name
          end

          def greet
            "Hello"
          end
        end
      RUBY

      chunks = RubyParser.parse(source)

      assert_equal 3, chunks.size

      klass = chunks.find { _1.chunk_type == "class" }
      assert_equal "User", klass.qualified_name
      assert_equal 1, klass.line_start
      assert_equal 9, klass.line_end

      init = chunks.find { _1.qualified_name == "User#initialize" }
      assert_equal "method", init.chunk_type
      assert_equal 2, init.line_start
    end

    def test_parses_nested_module_and_class
      source = <<~RUBY
        module Outer
          class Inner
            def work
            end
          end
        end
      RUBY

      chunks = RubyParser.parse(source)
      names = chunks.map(&:qualified_name)

      assert_includes names, "Outer"
      assert_includes names, "Outer::Inner"
      assert_includes names, "Outer::Inner#work"
    end

    def test_parses_class_methods_via_singleton
      source = <<~RUBY
        class Builder
          class << self
            def create
              new
            end
          end
        end
      RUBY

      chunks = RubyParser.parse(source)
      method = chunks.find { _1.chunk_type == "method" }

      assert_equal "Builder.create", method.qualified_name
    end

    def test_falls_back_to_sliding_window_on_invalid_ruby
      source = "def foo(\nend end end {"

      chunks = RubyParser.parse(source)

      assert chunks.any?
      assert_equal "window", chunks.first.chunk_type
    end

    def test_parses_rails_model_with_dsl
      source = <<~RUBY
        class User < ApplicationRecord
          has_many :posts
          validates :name, presence: true

          scope :active, -> { where(active: true) }

          def full_name
            "\#{first_name} \#{last_name}"
          end
        end
      RUBY

      chunks = RubyParser.parse(source)
      klass = chunks.find { _1.chunk_type == "class" }

      assert_includes klass.content, "has_many :posts"
      assert_includes klass.content, "validates :name"
      assert_includes klass.content, "scope :active"
    end
  end
end
