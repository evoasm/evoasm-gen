module Evoasm
  module Gen
    module Nodes
      class Node
        attr_reader :unit

        def traverse(&block)
          attrs = self.class.attributes
          attrs.each do |attr|
            value = send attr
            block[value]

            if value.is_a?(Node)
              value.traverse(&block)
            end
          end
        end

        def initialize(unit)
          @unit = unit
        end

        def self.own_attributes
          []
        end

        def self.attributes
          if self == Node
            []
          else
            superclass.attributes + own_attributes
          end
        end
      end

      def self.def_node(superclass, *attrs, &block)
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

          define_singleton_method :own_attributes do
            attrs.freeze
          end

          unless attrs.empty?
            superclass_attrs = superclass.attributes
            all_attrs = superclass_attrs + attrs

            class_eval <<~END
              def initialize(#{(%w(unit) + all_attrs).join(',')})
                super(#{(%w(unit) + superclass_attrs).join(',')})
                #{attrs.map { |attr| "@#{attr} = #{attr}" }.join("\n")}

                after_initialize
              end

              def hash
                super ^ #{attrs.map { |attr| "@#{attr}" }.join(' ^ ')}
              end

              def eql?(other)
                super(other) && #{attrs.map { |attr| "@#{attr} == other.#{attr}" }.join(' && ')}
              end
              alias == eql?

              private
              def after_initialize
              end
            END
          end

          class_eval &block if block
        end


      end
    end
  end
end
