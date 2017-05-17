require 'evoasm/gen/core_ext/string_io'

module Evoasm
  module Gen
    module Nodes
      class Enumeration

        def to_c(io = StringIO.new)
          raise 'name missing' unless name

          type_name = c_type_name

          io.puts "typedef enum #{type_name} {"
          io.indent do
            c_enum_body io
          end
          io.write '} '
          io.write type_name
          io.puts ';'

          c_bitsize_defines io
          c_bitmask_defines io

          io.string
        end

        def all_symbol_to_c
          unit.symbol_to_c "#{c_symbol_prefix(true)}_all", @prefix, const: true
        end

        def none_symbol_to_c
          unit.symbol_to_c "#{c_symbol_prefix(true)}_none", @prefix, const: true
        end

        def symbol_to_c(symbol_name)
          unit.symbol_to_c symbol_name, Array(@prefix) + [c_symbol_prefix], const: true
        end

        def to_ruby_ffi(io = StringIO.new)
          io.indent(absolute: 2) do
            io.puts "enum :#{ruby_ffi_type_name}, ["
            io.indent do
              ruby_ffi_enum_body io
            end
            io.puts ']'
          end

          io.string
        end

        private

        def c_bitsize_defines(io)
          if flags?
            io.puts "#define #{all_symbol_to_c} #{all_value}"
            io.puts "#define #{none_symbol_to_c} 0"
          else
            io.puts "#define #{bitsize_symbol_to_c } #{bitsize}"
            io.puts "#define #{bitsize_symbol_to_c true} #{bitsize true}"
          end
        end

        def c_bitmask_defines(io)
          io.puts "#define #{bitmask_symbol_to_c} 0x#{((1 << bitsize) - 1).to_s 16}"
          unless flags?
            io.puts "#define #{bitmask_symbol_to_c true} 0x#{((1 << bitsize(true)) - 1).to_s 16}"
          end
        end

        def c_enum_body(io)
          each do |symbol, value|
            symbol_name = symbol_to_c symbol
            c_value =
              if flags?
                "1 << #{value}"
              else
                value.to_s
              end
            io.puts "#{symbol_name} = #{c_value},"
          end

          each_alias do |symbol, value|
            io.puts "#{symbol_to_c symbol} = #{symbol_to_c value},"
          end

          io.puts none_symbol_to_c unless flags?

        end

        def ruby_ffi_enum_body(io)
          each do |symbol, value|
            symbol_name = symbol_to_ruby_ffi symbol
            symbol_value =
              if valid_symbol?(value)
                symbol_to_ruby_ffi value
              elsif flags?
                "1 << #{value}"
              else
                value.to_s
              end
            io.puts ":#{symbol_name}, #{symbol_value},", eol: "\n"
          end

          io.puts ":#{none_symbol_to_ruby_ffi}" unless flags?
        end

        def c_symbol_prefix(type = false)
          # convention: _id does not appear in symbol's name
          name(type: type).to_s.sub(/_id$/, '')
        end

        def c_type_name
          unit.symbol_to_c name(type: true), @prefix, type: true
        end

        def bitsize_symbol_to_c(optional = false)
          unit.symbol_to_c "#{c_symbol_prefix(true)}_bitsize#{optional ? '_opt' : ''}", @prefix, const: true
        end

        def bitmask_symbol_to_c(optional = false)
          unit.symbol_to_c "#{c_symbol_prefix(true)}_bitmask#{optional ? '_opt' : ''}", @prefix, const: true
        end

        def ruby_ffi_type_name
          p [@prefix, name]
          "#{@prefix ? "#{@prefix}_" : ''}#{name}"
        end

        def none_symbol_to_ruby_ffi
          unit.symbol_to_ruby_ffi 'none'
        end

        def symbol_to_ruby_ffi(symbol)
          unit.symbol_to_ruby_ffi symbol, Array(@prefix) + [c_symbol_prefix], const: true
        end
      end
    end
  end
end
