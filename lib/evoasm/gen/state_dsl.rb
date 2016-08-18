require 'evoasm/gen/state'
require 'evoasm/gen/nodes'

module Evoasm::Gen
  module StateDSL
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
          state
        end
      end
    end

    class DSLState
      include StateDSL

      def initialize(state)
        @__state__ = state
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
      add_action :set, name.to_sym, expression(value)
      @__state__.add_local_variable name if State.local_variable_name?(name)
    end

    def write(value = nil, size = nil)
      if Array === size && Array === value
        raise ArgumentError, 'values and sizes must have same length' unless value.size == size.size
      end
      add_action :write, expression(value), expression(size)
    end

    def unordered_writes(param_name, writes)
      writes = writes.map do |condition, write_args|
        [expression(condition), WriteAction.new(*expressions(write_args))]
      end

      add_action :unordered_writes, expression(param_name), writes
    end

    def call(func)
      add_action :call, func
    end

    def access(op, modes)
      add_action :access, op, modes
    end

    def recover_with(param, range = nil, **opts)
      @__state__.recovery << [param, range, opts]
    end

    def log(level, msg, *args)
      add_action :log, level, msg, *expressions(args)
    end

    def assert(*args)
      add_action :assert, expressions(args)
    end

    def calls?(name)
      @__state__.calls.include? name
    end

    def return!
      @__state__.returns = true
    end

    def error(code = nil, msg = nil, reg: nil, param: nil)
      add_action :error, code, msg, reg, param
      return!
    end

    def to(child = nil, **attrs, &block)
      if child.nil?
        child = State.new
        call_with_state block, child
      end

      @__state__.add_child child, nil, default_attrs(attrs)
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
        Operation.build arg.first, arg[1..-1]
      when String, Integer, FalseClass, TrueClass
        Literal.build arg
      when Symbol
        expr_s = arg.to_s
        if expr_s == expr_s.upcase
          Constant.new arg
        elsif param_name? arg
          Parameter.new arg
        else
          raise "unknown symbol '#{arg}'"
        end
      else
        raise ArgumentError, "unhandled argument type #{arg.class}"
      end
    end

    def add_action(*args)
      @__state__.actions << Action.build(*args)
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
