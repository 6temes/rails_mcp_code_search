require "prism"

module RailsMcpCodeSearch
  class RubyParser
    ParseError = Class.new(StandardError)
    Result = Data.define(:content, :line_start, :line_end, :chunk_type, :qualified_name)

    def self.parse(source, file_path: nil)
      new.parse(source, file_path:)
    end

    def parse(source, file_path: nil)
      result = Prism.parse(source)
      raise ParseError, result.errors.map(&:message).join(", ") unless result.success?

      visitor = Visitor.new(source)
      visitor.visit(result.value)
      visitor.chunks
    rescue ParseError
      SlidingWindowParser.parse(source, file_path:)
    end

    class Visitor < Prism::Visitor
      attr_reader :chunks

      def initialize(source)
        super()
        @source = source
        @lines = source.lines
        @scope_stack = []
        @chunks = []
      end

      def visit_class_node(node)
        visit_container(node, "class")
      end

      def visit_module_node(node)
        visit_container(node, "module")
      end

      def visit_def_node(node)
        name = node.name.to_s
        qualified = build_qualified_name(name, instance_method: true)
        add_chunk(node, "method", qualified)
      end

      def visit_singleton_class_node(node)
        # Extract class methods defined inside `class << self`
        @in_singleton = true
        super
        @in_singleton = false
      end

      private

      def visit_container(node, type)
        name = constant_name(node.constant_path)
        @scope_stack.push(name)

        qualified = @scope_stack.join("::")
        line_start = node.location.start_line
        line_end = node.location.end_line
        content = @lines[(line_start - 1)..(line_end - 1)].join
        @chunks << Result.new(content:, line_start:, line_end:, chunk_type: type, qualified_name: qualified)

        visit_child_nodes(node)

        @scope_stack.pop
      end

      def add_chunk(node, type, qualified_name)
        line_start = node.location.start_line
        line_end = node.location.end_line
        content = @lines[(line_start - 1)..(line_end - 1)].join
        @chunks << Result.new(content:, line_start:, line_end:, chunk_type: type, qualified_name:)
      end

      def build_qualified_name(method_name, instance_method: true)
        prefix = @scope_stack.join("::")
        separator = (@in_singleton ? "." : (instance_method ? "#" : "."))
        prefix.empty? ? method_name : "#{prefix}#{separator}#{method_name}"
      end

      def constant_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parts = []
          current = node
          while current.is_a?(Prism::ConstantPathNode)
            parts.unshift(current.name.to_s)
            current = current.parent
          end
          parts.unshift(current.name.to_s) if current.is_a?(Prism::ConstantReadNode)
          parts.join("::")
        else
          node.to_s
        end
      end
    end
  end
end
