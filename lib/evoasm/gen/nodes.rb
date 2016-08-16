require 'set'

module Evoasm
  module Gen
    class Action
      def self.expression_class(name)
        Gen.const_get :"#{name.capitalize}Action"
      end

      def self.build(name, *args)
        expression_class(name).new(*args)
      end
    end

    class WriteAction < Action
      attr_reader :value, :size

      def initialize(value, size)
        @value = value
        @size = size
      end
    end

    class LogAction < Action
      def initialize(level, msg, *args)
        @level = level
        @msg = msg
        @args = args
      end
    end

    class AccessAction < Action
      def initialize(reg, mode)
        @reg = reg
        @mode = mode
      end
    end

    class Expression
      attr_reader :name, :args

      def self.expression_class(name)
        Gen.const_get :"#{name.capitalize}Action"
      end

      def self.build(name, args)
        expression_class(name).new(name, args)
      end

      def to_s
        args_to_s = args.map(&:to_s).join(', ')
        "#{name}(#{args_to_s})"
      end
    end

    class BinaryExpression < Expression

    end

    Parameter = Struct.new :name
    Constant = Struct.new :name
  end
end
