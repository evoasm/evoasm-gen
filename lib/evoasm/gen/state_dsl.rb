require 'evoasm/gen/state'

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

    def exec(name, args)
      @__state__.actions << [name, args]
    end

    def set(name, value)
      raise ArgumentError, 'nil not allowed' if value.nil?
      exec :set, [name.to_sym, value]
      @__state__.add_local_variable name if State.local_variable_name?(name)
    end

    def write(value = nil, size = nil)
      if Array === size && Array === value
        raise ArgumentError, 'values and sizes must have same length' unless value.size == size.size
      end
      exec :write, [value, size]
    end

    def unordered_writes(param_name, writes)
      exec :unordered_writes, [param_name, writes]
    end

    def call(func)
      exec :call, [func]
    end

    def access(op, modes)
      exec :access, [op, modes]
    end

    def recover_with(param, range = nil, **opts)
      @__state__.recovery << [param, range, opts]
    end

    def log(level, msg, *args)
      exec :log, [level, msg, *args]
    end

    def assert(*args)
      exec :assert, args
    end

    def calls?(name)
      @__state__.calls.include? name
    end

    def ret
      @__state__.ret = true
    end

    def error(code = nil, msg = nil, reg: nil, param: nil)
      exec :error, [code, msg, reg, param]
      ret
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
      { priority: lowest_priority + 1 }.merge attrs
    end

    def else_to(state = nil, &block)
      to_if(:else, state, priority: LOWEST_PRIORITY, &block)
    end

    def to_if(*args, **attrs, &block)
      if block
        child = State.new
        call_with_state block, child

        args.compact!
      else
        child = args.pop
      end

      @__state__.add_child child, args, default_attrs(attrs)
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

    def call_with_state(block, state)
      prev_state = @__state__
      @__state__ = state
      result = block.call
      @__state__ = prev_state

      result
    end
  end
end
