require 'evoasm/gen/strio'
require 'evoasm/gen/translation/name_util'

module Evoasm
  module Gen
    class Enum
      attr_reader :name, :flags

      def initialize(name = nil, elems = [], prefix: nil, flags: false)
        @name = name
        @prefix = prefix
        @map = {}
        @counter = 0
        @flags = flags
        @aliases = {}
        add_all elems
      end

      def flags?
        @flags
      end

      def size
        @counter
      end

      def add(symbol)
        raise ArgumentError, 'can only add symbols or strings'\
          unless valid_symbol?(symbol)
        return if @map.key? symbol

        value = @counter
        @counter += 1

        @map[symbol] = value
      end

      def add_all(elems)
        elems.each do |symbol|
          add symbol
        end
      end

      def each(&block)
        @map.each &block
      end

      def each_alias(&block)
        @aliases.each &block
      end

      def symbols
        @map.keys
      end

      def alias?(symbol)
        @aliases.key? symbol
      end

      def alias(alias_symbol, symbol)
        @aliases[alias_symbol] = symbol
      end

      def bitsize(with_n = false)
        if flags?
          @map.size
        else
          Math.log2(max + 1 + (with_n ? 1 : 0)).ceil.to_i
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

      def symbol_name_prefix
        # convention: _id does not appear in symbol's name
        name.to_s.sub(/_id$/, '')
      end

      def valid_symbol?(symbol)
        symbol.is_a?(Symbol) || symbol.is_a?(String)
      end
    end

  end
end
