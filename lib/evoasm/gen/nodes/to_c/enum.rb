require 'evoasm/gen/strio'

module Evoasm
  module Gen
    module Nodes
      class Enum
        def to_c(io = StrIO.new)
          raise 'name missing' unless name

          type_name = c_type_name

          io.puts "enum #{type_name} {"
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
          io.write '} '
          io.write type_name
          io.puts ';'
          io.puts "#define #{bitsize_to_c} #{bitsize}"
          if flags?
            io.puts "#define #{all_symbol_to_c} #{all_value}"
          else
            io.puts "#define #{bitsize_to_c true} #{bitsize true}"
          end

          io.string
        end

        def c_type(typedef = false)
          "#{typedef ? '' : 'enum '}#{c_type_name}"
        end

        def all_symbol_to_c
          unit.symbol_to_c "#{symbol_name_prefix}_all", @prefix, const: true
        end

        def n_symbol_to_c
          unit.symbol_to_c "n_#{symbol_name_prefix}s", @prefix, const: true
        end

        def symbol_to_c(symbol_name)
          # convention: _id does not appear in symbol's name
          unit.symbol_to_c symbol_name, Array(@prefix) + [symbol_name_prefix], const: true
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

        private

        def c_type_name
          unit.symbol_to_c name, @prefix, type: true
        end

        def bitsize_to_c(with_n = false)
          unit.symbol_to_c "#{symbol_name_prefix}_bitsize#{with_n ? '_WITH_N' : ''}", @prefix, const: true
        end

        def ruby_ffi_type_name
          "#{@prefix}_#{name}"
        end

        def n_symbol_to_ruby_ffi
          unit.symbol_to_ruby_ffi "n_#{symbol_name_prefix}s"
        end

        def symbol_to_ruby_ffi(symbol)
          unit.symbol_to_ruby_ffi symbol, Array(@prefix) + [symbol_name_prefix], const: true
        end
      end
    end
  end
end
