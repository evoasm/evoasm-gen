require 'evoasm/gen/core_ext/string_io'
require 'evoasm/gen/nodes'

module Evoasm
  module Gen
    module Nodes
      class Enumeration < Node
        attr_reader :flags

        def initialize(unit, name, elems = [], prefix: nil, flags: false)
          super(unit)

          @name = name
          @prefix = prefix
          @map = {}
          @counter = 0
          @flags = flags
          @aliases = {}
          add_all elems
        end

        def name(type: false)
          if @name =~ /flag$/ && flags? && type
            "#{@name}s"
          else
            @name
          end
        end

        def flags?
          @flags
        end

        def size
          @counter
        end

        def add(symbol)
          unless valid_symbol?(symbol)
            raise ArgumentError, "can only add symbols or strings not '#{symbol.class}'"
          end

          return if @map.key? symbol
          return if @aliases.key? symbol

          value = @counter
          @counter += 1

          @map[symbol] = value
        end

        def add_all(symbols)
          symbols.each do |symbol|
            add symbol
          end
        end

        def aliases(symbol)
          aliases = []
          @aliases.each do |alias_symbol, symbol_|
            aliases << alias_symbol if symbol == symbol_
          end

          aliases
        end

        def each(&block)
          @map.each &block
        end

        def each_alias(&block)
          @aliases.each &block
        end

        def bitmap(&block)
          symbols.each_with_index.inject(0) do |acc, (flag, index)|
            if block[flag, index]
              acc | (1 << index)
            else
              acc
            end
          end
        end

        def symbols
          @map.keys
        end

        def include?(symbol)
          @map.include?( symbol) || @aliases.include?(symbol)
        end

        def alias?(symbol)
          @aliases.key? symbol
        end

        def define_alias(alias_symbol, symbol)
          @aliases[alias_symbol] = symbol
        end

        def aliasee(symbol)
          @aliases[symbol]
        end

        def bitsize(optional = false, flags: false)
          if flags? || flags
            @map.size
          else
            Math.log2(max + 1 + (optional ? 1 : 0)).ceil.to_i
          end
        end

        def max
          @map.each_with_index.inject(0) do |acc, (_index, (k, v))|
            if v
              [v + 1, acc + 1].max
            else
              acc + 1
            end
          end - 1
        end

        private

        def all_value
          (2**@map.size) - 1
        end

        def valid_symbol?(symbol)
          symbol.is_a?(::Symbol) || symbol.is_a?(String)
        end
      end
    end
  end
end
