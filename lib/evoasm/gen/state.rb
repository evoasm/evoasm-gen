require 'set'

module Evoasm::Gen
  State = Struct.new(:children, :actions, :returns, :local_variables) do
    attr_accessor :id, :comment, :parents

    def initialize
      self.children = []
      self.parents = []
      self.actions = []
      self.local_variables = []
    end

    def transitive_local_variables
      child_local_variables = children.map do |child, _, _|
        child.transitive_local_variables
      end
      all_local_variables = (local_variables + child_local_variables)
      all_local_variables.flatten!
      all_local_variables.uniq!

      all_local_variables
    end

    def self.local_variable_name?(name)
      name.to_s[0] == '_'
    end

    def self.shared_variable_name?(name)
      name.to_s[0] == '@'
    end

    def add_local_variable(name)
      unless self.class.local_variable_name? name
        raise ArgumentError, 'local_variables must start with underscore'
      end

      local_variables << name unless local_variables.include? name
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
            "<b> else</b><br></ br> \ n "
          else
            "<b> if
                                                                                           </b> #{expr_to_s condition}<br></ br> \ n "
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
