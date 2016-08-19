module Evoasm
  module Gen
    module Nodes
      class Node
        attr_reader :unit

        def initialize(unit)
          @unit = unit
        end
      end

      def self.def_node(superclass = Node, *attrs, &block)
        unless superclass <= Node
          raise ArgumentError, 'superclass must be kind of Node'
        end

        Class.new superclass do
          attrs.each do |attr|

            reader_name = attr
            writer_name = :"#{attr}="

            define_method reader_name do
              instance_variable_get :"@#{attr}"
            end

            define_method writer_name do |value|
              instance_variable_set :"@#{attr}", value
            end
            private writer_name

          end

          class_eval <<~END
            def initialize(unit#{attrs && attrs.join(',')})
              super(unit)
              #{attrs.map { |attr| "@#{attr} = #{attr}"}.join("\n")}

              after_initialize
            end

            def hash
              #{attrs.map { |attr| "@#{attr}" }.join(' ^ ')}
            end

            def eql?(other)
              #{attrs.map { |attr| "@#{attr} == other.#{attr}" }.join(' && ')}
            end
            alias == eql?

            private
            def after_initialize
            end
          END

          class_eval &block if block
        end


      end
    end
  end
end
