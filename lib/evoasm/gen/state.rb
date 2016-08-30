require 'set'

module Evoasm
  module Gen
    class State
      attr_reader :children, :actions, :own_local_variables
      attr_accessor :id, :comment, :parents, :returns

      def initialize
        @children = []
        @parents = []
        @actions = []
        @own_local_variables = []
      end

      def local_variables
        child_local_variables = children.map do |child, _, _|
          child.local_variables
        end
        all_local_variables = own_local_variables + child_local_variables
        all_local_variables.flatten!
        all_local_variables.uniq!

        all_local_variables
      end

      def ordered_children
        return @ordered_children if @ordered_children
        sorted_children = @children.sort_by { |_, _, attrs| attrs[:priority] }

        @ordered_children =
          if sorted_children.size == 2
            first_child, second_child = sorted_children

            _, first_condition, = first_child
            _, second_condition, = second_child

            if second_condition.is_a?(Nodes::Else)
              case first_condition
              when Nodes::TrueLiteral
                [first_child]
              when Nodes::FalseLiteral
                [second_child]
              else
                sorted_children
              end
            else
              raise
            end
          else
            sorted_children
          end
      end

      def can_get_stuck?
        return false if returns?
        return false if else_child?

        raise state.actions.inspect if children.empty?

        return false if children.any? do |_child, condition|
          condition.is_a?(Nodes::TrueLiteral)
        end

        true
      end

      def else_child?
        @children.any? { |_, condition,| condition.is_a?(Nodes::Else) }
      end

      def deterministic?
        n_children = children.size

        n_children <= 1 ||
          (n_children == 2 && else_child?)
      end

      def inlineable?
        parents.size == 1 && parents.first.deterministic?
      end

      def add_local_variable(name)
        @own_local_variables << name unless @own_local_variables.include? name
      end

      protected def add_parent(parent)
        parents << parent unless parents.include? parent
      end

      def add_child(child, condition = nil, priority)
        child.add_parent self
        children << [child, condition, priority]
      end

      %i(sets asserts calls writes debugs).each do |name|
        action_name = name.to_s[0..-2].to_sym
        define_method name do
          actions.select { |action, _| action == action_name }
            .map { |_, args| args }
        end
      end

      private def roots
        return [self] if parents.empty?
        parents.flat_map(&:roots)
      end

      def root
        roots = self.roots
        raise 'multiple roots' if roots.size > 1
        roots.first
      end

      def empty?
        actions.empty?
      end

      def terminal?
        children.empty?
      end

      def returns?
        !!returns
      end

      def to_gv
        require 'gv'

        graph = GV::Graph.open 'ast'
        graph[:ranksep] = 1.5
        graph[:statesep] = 0.8
        __to_gv__ graph
        graph
      end

      def __to_gv__(graph, gv_parent = nil, condition = nil, attrs = {}, index = nil, seen = {})
        if seen.key?(self)
          # return
        else
          seen[self] = true
        end

        edge_label = ''
        state_label = ''

        if condition
          edge_label <<
            if condition.first == :else
              "<b>else</b><br></br>\n"
            else
              "<b>if</b> #{expr_to_s condition}<br></br>\n"
            end
        end

        if attrs
          attrs.each do |name, value|
            edge_label << "<b> #{name}</b>: #{value}<br></br>\n"
          end
        end

        actions.each do |name, args|
          state_label << send(:"label_#{name}", *args)
        end

        state_label << "<i>#{comment}</i>\n" if comment

        gv_state = graph.expression object_id.to_s,
                                    shape: (self.returns? ? :house : (state_label.empty? ? :point : :box)),
                                    label: graph.html(state_label)

        children.each_with_index do |(child, condition, attrs), index|
          child.__to_gv__(graph, gv_state, condition, attrs, index, seen)
        end

        if gv_parent
          graph.edge gv_parent.name + '.' + gv_state.name + index.to_s,
                     gv_parent, gv_state,
                     label: graph.html(edge_label)
        end

        graph
      end

      private

      def label_set(name, value, _options = {})
        "<b>set</b> #{name} := #{expr_to_s value}<br></br>"
      end

      def label_assert(condition)
        "<b>assert</b> #{expr_to_s condition}<br></br>"
      end

      def label_call(name)
        "<b>call</b> #{name}<br></br>"
      end

      def label_debug(_format, *_args)
        ''
      end

      def label_write(value, size)
        label =
          if value.is_a?(Integer) && size.is_a?(Integer)
            if size == 8
              'x%x' % value
            else
              "b%0#{size}b" % value
            end
          elsif size.is_a? Array
            Array(value).zip(Array(size)).map do |v, s|
              "#{expr_to_s v} [#{expr_to_s s}]"
            end.join ', '
          else
            "#{expr_to_s value} [#{expr_to_s size}]"
          end
        "<b>output</b> #{label}<br></br>"
      end
    end
  end
end
