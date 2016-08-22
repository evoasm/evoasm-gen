require 'evoasm/gen/state'
require 'evoasm/gen/nodes/others'
require 'evoasm/gen/nodes/actions'

module Evoasm
  module Gen
    module StateDSL
      include Nodes

      LOWEST_PRIORITY = 999

      def self.included(base)
        base.send :extend, ClassMethods
      end

      module ClassMethods
        def static_state(name)
          f = instance_method(name)
          var_name = :"@#{name}"

          define_method(name) do
            return instance_variable_get var_name if instance_variable_defined? var_name
            state = State.new
            call_with_state f.bind(self), state

            instance_variable_set var_name, state
          end
        end
      end

      def comment(comment = nil)
        if comment
          @__state__.comment = comment
        else
          @__state__.comment
        end
      end

      def set(name, value)
        raise ArgumentError, 'nil not allowed' if value.nil?
        add_new_action :set, expression(name.to_sym), expression(value)
        @__state__.add_local_variable name if State.local_variable_name?(name)
      end

      def new_write_action(value, size)
        values, sizes =
          case size
          when Array
            if value.size == size.size
              [expressions(value), expressions(size)]
            else
              raise ArgumentError, "values and sizes must have same length (#{value.size} and #{size.size})"
            end
          else
            [[expression(value)], [expression(size)]]
          end
        Nodes::WriteAction.new(unit, values, sizes)
      end

      def write(value, size)
        add_action new_write_action(value, size)
      end

      def unordered_writes(param_name, writes)
        writes = writes.map do |condition, write_args|
          [expression(condition), new_write_action(*write_args)]
        end

        parameter = expression(param_name)
        unordered_writes = UnorderedWrites.new(unit, writes)

        parameter.domain = unordered_writes.domain

        add_new_action :unordered_writes,
                       parameter,
                       unordered_writes
      end

      def call(func)
        add_new_action :call, func
      end

      def access(op, modes)
        add_new_action :access, op, modes
      end

      def recover_with(param, range = nil, **opts)
        @__state__.recovery << [param, range, opts]
      end

      def log(level, msg, *args)
        add_new_action :log, level, msg, expressions(args)
      end

      def assert(*args)
        add_new_action :assert, expressions(args)
      end

      def calls?(name)
        @__state__.calls.include? name
      end

      def return!
        @__state__.returns = true
      end

      def error(code = nil, msg = nil, reg: nil, param: nil)
        add_new_action :error, ErrorCode.new(unit, code), StringLiteral.new(unit, msg),
                       RegisterConstant.new(unit, reg), ParameterVariable.new(unit, param)
        return!
      end

      def to(child = nil, **attrs, &block)
        if child.nil?
          child = State.new
          call_with_state block, child
        end

        @__state__.add_child child, TrueLiteral.new(unit), default_attrs(attrs)
        child
      end

      def lowest_priority
        @__state__.children.map { |_, _, attrs| attrs[:priority] }.max || 0
      end

      def default_attrs(attrs)
        {priority: lowest_priority + 1}.merge attrs
      end

      def else_to(state = nil, &block)
        to_if(:else, state, priority: LOWEST_PRIORITY, &block)
      end

      def to_if(*condition, **attrs, &block)
        if block
          child = State.new
          call_with_state block, child

          condition.compact!
        else
          child = condition.pop
        end

        condition = condition.first if condition.size == 1

        @__state__.add_child child, expression(condition), default_attrs(attrs)
        child
      end

      def self_state
        @__state__
      end

      def state(*args, &block)
        if args.size == 1 && State === args.first
          call_with_state(block, args.first)
        else
          State.new(*args).tap do |s|
            call_with_state(block, s)
          end
        end
      end

      private

      def expressions(args)
        args.map { |arg| expression(arg) }
      end

      def expression(arg)
        case arg
        when Array
          op_name = arg.first
          op_args = expressions(arg[1..-1])

          Operation.new unit, op_name, op_args
        when String, Integer, FalseClass, TrueClass
          new_literal arg
        when ::Symbol
          expr_s = arg.to_s
          if expr_s == expr_s.upcase
            if Gen::X64::REGISTER_NAMES.include? arg
              RegisterConstant.new unit, arg
            else
              Constant.new unit, arg
            end
          elsif expr_s[0] == '_'
            LocalVariable.new unit, arg[1..-1]
          elsif expr_s[0] == '@'
            SharedVariable.new unit, arg[1..-1]
          elsif parameter_name? arg
            ParameterVariable.new unit, arg
          elsif arg == :else
            Else.new unit
          else
            raise "unknown symbol '#{arg}'"
          end
        else
          raise ArgumentError, "unhandled argument type #{arg.class}"
        end
      end

      def add_new_action(*args)
        add_action new_action(*args)
      end

      def add_action(action)
        @__state__.actions << action
      end

      def new_action(name, *args)
        action_class = Nodes.const_get :"#{name.to_s.camelcase}Action"
        action_class.new(unit, *args)
      end

      def new_literal(value)
        literal_class =
          case value
          when String
            StringLiteral
          when Integer
            IntegerLiteral
          when TrueClass
            TrueLiteral
          when FalseClass
            FalseLiteral
          end

        if literal_class < ValueLiteral
          literal_class.new unit, value
        else
          literal_class.new unit
        end
      end

      def call_with_state(block, state)
        prev_state = @__state__
        @__state__ = state
        result = block.call
        @__state__ = prev_state

        result
      end
    end
  end
end
