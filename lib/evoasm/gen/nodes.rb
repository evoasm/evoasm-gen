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
      attr_reader :code, :msg, :reg, :param

      def initialize(code, msg, reg, param)
        @code = code
        @msg = msg
        @reg = reg
        @param = param
      end
    end

    class Expression
    end

    class Operation < Expression
      attr_reader :name, :args

      def self.build(name, args)
        new name, args
      end

      def initialize(name, args)
        @name = name
        @args = args

        simplify!
      end

      def to_s
        args_to_s = args.map(&:to_s).join(', ')
        "#{name}(#{args_to_s})"
      end

      private

      def simplify!
        while simplify_
        end
      end

      def simplify_
        new_name, new_args =
          case name
          when :neq
            [:not, [Operation.build(:eq, args)]]
          when :false?
            [:eq, [*args, 0]]
          when :true?
            [:not, [Operation.build(:false?, *args)]]
          when :unset?
            [:not, [Operation.build(:set?, *args)]]
          when :in?
            args = self.args[1..-1].map do |arg|
              Operation.build(:eq, [self.args.first, arg])
            end
            [:or, args]
          when :not_in?
            [:not, [Operation.build(:in?, args)]]
          end

        if new_name
          @name = new_name
          @args = new_args
          true
        else
          false
        end
      end
    end

    class Else < Expression
    end

    class HelperOperation < Operation
    end

    class PermutationTable
      attr_reader :size

      def self.cached(size)
        @cache ||= Hash.new { |h, k| h[k] = new size }
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
        @cache ||= Hash.new { |h, k| h[k] = new k }
        @cache[writes]
      end

      def initialize(writes)
        @writes = writes
        @permutation_table = PermutationTable.cached writes.size
      end
    end

    class Literal < Expression
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

        if literal_class < ValueLiteral
          literal_class.new value
        else
          literal_class.new
        end
      end
    end

    class ValueLiteral < Literal
      attr_reader :value

      def initialize(value)
        @value = value
      end
    end

    class StringLiteral < ValueLiteral
    end

    class IntegerLiteral < ValueLiteral
    end

    class TrueLiteral < Literal
    end

    class FalseLiteral < Literal
    end

    class Symbol < Expression
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

    class Constant < Symbol
    end

    class ErrorCode < Constant
    end

    class Register < Constant
    end

    class Parameter < Constant
    end

    class LocalVariable < Symbol
    end

    class SharedVariable < Symbol
    end
  end
end
