require 'evoasm/gen/strio'
require 'evoasm/gen/name_util'

module Evoasm
  module Gen
    class Enum
      include NameUtil

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

      def to_ruby_ffi(io = StrIO.new)
        io.indent(2) do
          io.puts "enum :#{ruby_ffi_type_name}, ["
          io.indent do
            each do |symbol, value|
              symbol_name = symbol_to_ruby_ffi symbol
              symbol_value =
                if valid_symbol?(value)
                  symbol_to_ruby_ffi value
                else
                  if flags?
                    "1 << #{value}"
                  else
                    "#{value}"
                  end
                end
              io.puts ":#{symbol_name}, #{symbol_value},", eol: "\n"
            end
            unless flags?
              io.puts ":#{n_symbol_to_ruby_ffi}"
            end
          end
          io.puts ']'
        end

        io.string
      end

      def to_c(io = StrIO.new, typedef: true)
        raise 'name missing' unless name

        type_name = c_type_name

        io.puts "#{typedef ? 'typedef ' : ''}enum #{type_name} {"
        io.indent do
          each do |symbol, value|
            symbol_name = symbol_to_c symbol
            c_value =
              if flags?
                "1 << #{value}"
              else
                "#{value}"
              end
            io.puts "#{symbol_name} = #{c_value},"
          end

          each_alias do |symbol, value|
            io.puts "#{symbol_to_c symbol} = #{symbol_to_c value},"
          end

          unless flags?
            io.puts n_symbol_to_c
          end
        end
        io.write '}'
        io.write " #{type_name}" if typedef
        io.puts ';'
        io.puts "#define #{bitsize_to_c} #{bitsize}"
        if flags?
          io.puts "#define #{all_symbol_to_c} #{all_value}"
        else
          io.puts "#define #{bitsize_to_c true} #{bitsize true}"
        end

        io.string
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

      def c_type(typedef = false)
        "#{typedef ? '' : 'enum '}#{c_type_name}"
      end

      def all_symbol_to_c
        name_to_c "#{symbol_name_prefix}_all", @prefix, const: true
      end

      def n_symbol_to_c
        name_to_c "n_#{symbol_name_prefix}s", @prefix, const: true
      end

      def symbol_to_c(symbol_name)
        # convention: _id does not appear in symbol's name
        name_to_c symbol_name, Array(@prefix) + [symbol_name_prefix], const: true
      end

      private
      def all_value
        (2**@map.size) - 1
      end

      def c_type_name
        name_to_c name, @prefix, type: true
      end

      def ruby_ffi_type_name
        "#{@prefix}_#{name}"
      end

      def bitsize_to_c(with_n = false)
        name_to_c "#{symbol_name_prefix}_bitsize#{with_n ? '_WITH_N' : ''}", @prefix, const: true
      end

      def n_symbol_to_ruby_ffi
        name_to_ruby_ffi "n_#{symbol_name_prefix}s"
      end

      def symbol_name_prefix
        # convention: _id does not appear in symbol's name
        name.to_s.sub(/_id$/, '')
      end

      def symbol_to_ruby_ffi(symbol)
        name_to_ruby_ffi symbol, Array(@prefix) + [symbol_name_prefix], const: true
      end

      def valid_symbol?(symbol)
        symbol.is_a?(Symbol) || symbol.is_a?(String)
      end
    end
  end
end
