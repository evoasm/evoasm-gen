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

      def eql?(other)
        other.is_a?(self.class) &&
          value == other.value &&
          size == other.size
      end
      alias == eql?

      def hash
        value.hash + size.hash
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

    class SetAction < Action
      attr_reader :variable, :value

      def initialize(variable, value)
        @variable = variable
        @value = value
      end
    end

    class UnorderedWritesAction < Action
      attr_reader :param, :unordered_writes

      def initialize(param, writes)
        @param = param
        @unordered_writes = UnorderedWrites.cached writes
      end
    end

    class ErrorAction < Action
      attr_reader :code, msg, reg, param
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
        when :and, :or, :eq, :shl, :mod, :add
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
      def lhs
        args[0]
      end

      def rhs
        args[1]
      end
    end

    class HelperOperation < Operation
    end

    class PermutationTable
      attr_reader :size

      def self.cached(size)
        @cache ||= Hash.new { |h, k| h[k] = new size}
        @cache[size]
      end

      def initialize(size)
        @size = size
      end
    end

    class UnorderedWrites
      attr_reader :writes
      attr_reader :permutation_table

      def self.cached(writes)
        @cache ||= Hash.new { |h, k| h[k] = new k}
        @cache[writes]
      end

      def initialize(writes)
        @writes = writes
        @permutation_table = PermutationTable.cached writes.size
      end
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

    class SymbolExpression < Expression
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def hash
        name.hash
      end

      def eql?(other)
        other.is_a?(self.class) && name == other.name
      end
      alias == eql?
    end

    class Parameter < SymbolExpression
    end

    class Constant < SymbolExpression
    end

    class LocalVariable < SymbolExpression
    end

    class SharedVariable < SymbolExpression
    end
  end
end
