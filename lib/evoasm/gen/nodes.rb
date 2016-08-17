require 'set'
require 'evoasm/gen/core_ext/string'

module Evoasm
  module Gen
    class Action
      def self.expression_class(name)
        Gen.const_get :"#{name.to_s.camelcase}Action"
      end

      def self.build(name, *args)
        expression_class(name).new(*args)
      end
    end

    class WriteAction < Action
      attr_reader :value, :size

      def initialize(value, size)
        raise if value.nil?
        @value = value
        @size = size
      end
    end

    class LogAction < Action
      attr_reader :level, :msg, :args

      def initialize(level, msg, *args)
        @level = level
        @msg = msg
        @args = args
      end
    end

    class AccessAction < Action
      attr_reader :reg, :modes

      def initialize(reg, modes)
        @reg = reg
        @modes = modes
      end
    end

    class CallAction < Action
      attr_reader :state_machine

      def initialize(state_machine)
        @state_machine = state_machine
      end
    end

    class UnorderedWritesAction < Action
      attr_reader :params, :writes

      def initialize(params, writes)
        @params = params
        @writes = writes
      end
    end

    class Expression
      def to_s
        args_to_s = args.map(&:to_s).join(', ')
        "#{name}(#{args_to_s})"
      end
    end

    class Operation < Expression
      attr_reader :name, :args

      def self.operation_class(name)
        case name
        when :and, :or, :eq
          BinaryOperation
        else
          raise "unknown operation '#{name}'"
        end
      end

      def self.build(name, args)
        operation_class(name).new name, args
      end

      def initialize(name, args)
        @name = name
        @args = args
      end
    end

    class BinaryOperation < Operation
    end

    class HelperOperation < Operation
    end


    class Literal < Expression
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def self.build(value)
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

        literal_class.new value
      end
    end

    class StringLiteral < Literal
    end

    class IntegerLiteral < Literal
    end

    class TrueLiteral < Literal
    end

    class FalseLiteral < Literal
    end

    Parameter = Struct.new :name
    Constant = Struct.new :name
  end
end
