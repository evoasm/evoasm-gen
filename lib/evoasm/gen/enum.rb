require 'evoasm/gen/strio'
require 'evoasm/gen/name_util'

module Evoasm
  module Gen
    class Enum
      include NameUtil

      attr_reader :name, :flags
      alias_method :flags?, :flags

      def initialize(name = nil, elems = [], prefix: nil, flags: false)
        @name = name
        @prefix = prefix
        @map = {}
        @counter = 0
        @flags = flags
        add_all elems
      end

      def size
        @counter
      end

      def to_ruby_ffi(io = StrIO.new)
        io.indent(2) do
          io.puts "enum :#{ruby_ffi_type_name}, ["
          io.indent do
            each do |elem, value|
              elem_name = elem_name_to_ruby_ffi elem
              elem_value =
                if valid_elem?(value)
                  raise
                  elem_name_to_ruby_ffi value
                else
                  if flags?
                    "1 << #{value}"
                  else
                    "#{value}"
                  end
                end
              io.puts ":#{elem_name}, #{elem_value}," , eol: "\n"
            end
            unless flags?
              io.puts ":#{n_elem_const_name_to_ruby_ffi}"
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
          each do |elem, value|
            elem_name = elem_name_to_c elem
            c_value =
              if valid_elem?(value)
                elem_name_to_c value
              else
                if flags?
                  "1 << #{value}"
                else
                  "#{value}"
                end
              end
            io.puts "#{elem_name} = #{c_value},"
          end
          unless flags?
            io.puts n_elem_const_name_to_c
          end
        end
        io.write '}'
        io.write " #{type_name}" if typedef
        io.puts ';'
        io.puts "#define #{bitsize_to_c} #{bitsize}"
        if flags?
          io.puts "#define #{all_to_c} #{all_value}"
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

      def all_value
        (2**@map.size) - 1
      end

      def keys
        @map.keys
      end

      def add(elem, alias_elem = nil)
        fail ArgumentError, 'can only add symbols or strings' \
          unless valid_elem?(elem) && (!alias_elem || valid_elem?(alias_elem))

        return if @map.key? elem

        value = alias_elem || @counter
        @counter += 1 if alias_elem.nil?

        @map[elem] = value
      end

      def add_all(elems)
        elems.each do |elem|
          add elem
        end
      end

      def each(&block)
        return to_enum(:each) if block.nil?
        @map.each_key do |k|
          block[k, self[k]]
        end
      end

      def alias(key)
        key = @map[key]
        case key
        when Symbol, String
          key
        else
          nil
        end
      end

      def [](elem)
        value = @map[elem]

        if @map.key? value
          @map.fetch value
        else
          value
        end
      end

      def all_to_c
        name_to_c "#{prefix_name}_all", @prefix, const: true
      end

      def n_elem_const_name_to_c
        name_to_c "n_#{prefix_name}s", @prefix, const: true
      end

      private
      def c_type_name
        name_to_c name, @prefix, type: true
      end

      def ruby_ffi_type_name
        "#{@prefix}_#{name}"
      end

      def bitsize_to_c(with_n = false)
        name_to_c "#{prefix_name}_bitsize#{with_n ? '_WITH_N' : ''}", @prefix, const: true
      end

      def n_elem_const_name_to_ruby_ffi
        # convention: _id does not appear in element's name
        name_to_ruby_ffi "n_#{prefix_name}s"
      end

      def prefix_name
        name.to_s.sub(/_id$/, '')
      end

      def elem_name_to_c(elem_name)
        # convention: _id does not appear in element's name
        name_to_c elem_name, Array(@prefix) + [prefix_name], const: true
      end

      def elem_name_to_ruby_ffi(elem_name)
        name_to_ruby_ffi elem_name, Array(@prefix) + [prefix_name], const: true
      end

      def valid_elem?(elem)
        elem.is_a?(Symbol) || elem.is_a?(String)
      end
    end
  end
end
