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
          unit.symbol_to_c "#{c_symbol_prefix}_all", @prefix, const: true
        end

        def n_symbol_to_c
          unit.symbol_to_c "n_#{c_symbol_prefix}s", @prefix, const: true
        end

        def symbol_to_c(symbol_name)
          unit.symbol_to_c symbol_name, Array(@prefix) + [c_symbol_prefix], const: true
        end

        def to_ruby_ffi(io = StringIO.new)
          io.indent(2) do
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
          io.puts "#define #{bitsize_symbol_to_c} #{bitsize}"
          if flags?
            io.puts "#define #{all_symbol_to_c} #{all_value}"
          else
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

          io.puts n_symbol_to_c unless flags?

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

          io.puts ":#{n_symbol_to_ruby_ffi}" unless flags?
        end

        def c_symbol_prefix
          # convention: _id does not appear in symbol's name
          name.to_s.sub(/_id$/, '')
        end

        def c_type_name
          unit.symbol_to_c name, @prefix, type: true
        end

        def bitsize_symbol_to_c(with_n = false)
          unit.symbol_to_c "#{c_symbol_prefix}_bitsize#{with_n ? '_WITH_N' : ''}", @prefix, const: true
        end

        def bitmask_symbol_to_c(with_n = false)
          unit.symbol_to_c "#{c_symbol_prefix}_bitmask#{with_n ? '_WITH_N' : ''}", @prefix, const: true
        end

        def ruby_ffi_type_name
          "#{@prefix}_#{name}"
        end

        def n_symbol_to_ruby_ffi
          unit.symbol_to_ruby_ffi "n_#{c_symbol_prefix}s"
        end

        def symbol_to_ruby_ffi(symbol)
          unit.symbol_to_ruby_ffi symbol, Array(@prefix) + [c_symbol_prefix], const: true
        end
      end
    end
  end
end
