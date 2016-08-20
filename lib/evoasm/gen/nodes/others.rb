require 'set'
require 'evoasm/gen/core_ext/string'

module Evoasm
  module Gen
    module Nodes

      Expression = def_node Node
      Operation = def_node Expression, :name, :args do
        def to_s
          args_to_s = args.map(&:to_s).join(', ')
          "#{name}(#{args_to_s})"
        end

        private

        def after_initialize
          simplify!
        end

        def simplify!
          while simplify_
          end
        end

        def simplify_
          new_name, new_args =
            case name
            when :neq
              [:not, [Operation.new(unit, :eq, args)]]
            when :false?
              [:eq, [*args, 0]]
            when :true?
              [:not, [Operation.new(unit, :false?, *args)]]
            when :unset?
              [:not, [Operation.new(unit, :set?, *args)]]
            when :in?
              args = self.args[1..-1].map do |arg|
                Operation.new(unit, :eq, [self.args.first, arg])
              end
              [:or, args]
            when :not_in?
              [:not, [Operation.new(unit, :in?, args)]]
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

      Else = def_node Expression
      HelperOperation = def_node Operation do
        HELPER_NAMES = %i(reg_code)

        def self.helper_name?(name)
          HELPER_NAMES.include? name

        end
      end

      PermutationTable = def_node Node, :size do
        def self.cached(unit, size)
          @cache ||= Hash.new { |h, k| h[k] = new *k }
          @cache[[unit, size]]
        end
      end

      UnorderedWrites = def_node Node, :writes do
        attr_reader :permutation_table

        def self.cached(unit, writes)
          @cache ||= Hash.new { |h, k| h[k] = new *k }
          @cache[[unit, writes]]
        end

        private

        def after_initialize
          @permutation_table = PermutationTable.cached unit, writes.size
        end
      end

      Literal = def_node Expression
      ValueLiteral = def_node Literal, :value
      StringLiteral = def_node ValueLiteral
      IntegerLiteral = def_node ValueLiteral
      TrueLiteral = def_node Literal
      FalseLiteral = def_node Literal
      Symbol = def_node Expression, :name
      Constant = def_node Symbol
      ErrorCode = def_node Constant
      RegisterConstant = def_node Constant
      ParameterVariable = def_node Symbol
      LocalVariable = def_node Symbol
      SharedVariable = def_node Symbol
      Parameter = def_node Node
    end
  end
end
