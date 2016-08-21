require 'set'
require 'evoasm/gen/core_ext/string'

module Evoasm
  module Gen
    module Nodes

      Expression = def_node Node
      Operation = def_node Expression, :name, :args do

        HELPER_NAMES = %i(reg_code set? log2 disp_size)

        def to_s
          args_to_s = args.map(&:to_s).join(', ')
          "#{name}(#{args_to_s})"
        end

        private

        def helper?
          HELPER_NAMES.include? name
        end

        def after_initialize
          unless args.all? { |arg| arg.is_a? Node }
            raise ArgumentError, 'operation arguments must be kind of node'
          end
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
              [:eq, [*args, IntegerLiteral.new(unit, 0)]]
            when :true?
              [:not, [Operation.new(unit, :false?, args)]]
            when :unset?
              [:not, [Operation.new(unit, :set?, args)]]
            when :in?
              mapped_args = args[1..-1].map do |arg|
                Operation.new(unit, :eq, [args.first, arg])
              end
              [:or, mapped_args]
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

      PermutationTable = def_node Node, :width do
        def table
          @table ||= (0...width).to_a.permutation.to_a
        end

        def height
          table.size
        end
      end

      UnorderedWrites = def_node Node, :writes do
        attr_reader :permutation_table

        def domain
          Domain.new unit, (0...@permutation_table.height)
        end

        private

        def after_initialize
          @permutation_table = unit.find_or_create_node PermutationTable, width: writes.size
        end
      end

      Domain = def_node Node, :values do
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
      ParameterVariable = def_node Symbol do
        attr_accessor :domain
      end
      LocalVariable = def_node Symbol
      SharedVariable = def_node Symbol
      Parameter = def_node Node, :name, :domain
    end
  end
end
