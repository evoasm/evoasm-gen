module Evoasm
  module Gen
    module Nodes
      class Node
        attr_reader :unit

        class << self
          def own_attributes
            []
          end

          def attributes
            if self == Node
              []
            else
              superclass.attributes + own_attributes
            end
          end

          def attrs(*attrs)
            return if attrs.empty?

            attrs.each do |attr|

              ivar_name = attr_instance_variable_name attr
              writer_name = attr_writer_name attr
              reader_name = attr_reader_name(attr)

              define_method reader_name do
                instance_variable_get ivar_name
              end

              define_method writer_name do |value|
                instance_variable_set ivar_name, value
              end
              private writer_name
            end

            define_singleton_method :own_attributes do
              attrs.freeze
            end

            superclass_attrs = superclass.attributes
            all_attrs = superclass_attrs + attrs

            parameter_list = (%w(unit) + all_attrs).map do |attr|
              attr_parameter_name attr
            end.join(',')

            super_argument_list = (%w(unit) + superclass_attrs).map do |attr|
              attr_parameter_name attr
            end.join(',')

            class_eval <<~END
              def initialize(#{parameter_list})
                super(#{super_argument_list})
                #{attrs.map { |attr| "#{attr_instance_variable_name attr} = #{attr_parameter_name attr}" }.join("\n")}

                after_initialize
              end

              def hash
                super ^ #{attrs.map { |attr| "#{attr_instance_variable_name attr}.hash" }.join(' ^ ')}
              end

              def eql?(other)
                super(other) && #{attrs.map { |attr| "#{attr_instance_variable_name attr} == other.#{attr_reader_name attr}" }.join(' && ')}
              end
              alias == eql?

              private
              def after_initialize
              end
            END
          end

          private

          def attr_reader_name(attr)
            attr
          end

          def attr_parameter_name(attr)
            attr_remove_predicate_suffix attr
          end

          def attr_remove_predicate_suffix(attr)
            attr.to_s.sub /\?$/, ''
          end

          def attr_writer_name(attr)
            :"#{attr_remove_predicate_suffix attr}="
          end

          def attr_instance_variable_name(attr)
            :"@#{attr_remove_predicate_suffix attr}"
          end
        end

        def initialize(unit)
          @unit = unit
        end

        def eql?(other)
          other.is_a?(self.class)
        end

        def inspect(toplevel = false)
          attr_str = self.class.attributes.map do |attr|
            "#{attr}:#{send(attr).inspect}"
          end.join(' ')
          "<#{self.class.inspect} #{attr_str}>"
        end

        def traverse(&block)
          attrs = self.class.attributes
          attrs.each do |attr|
            value = send attr
            traverse_(value, &block)
          end
        end

        def match?(attrs = {})
          attrs.all? do |attr, value|
            send(attr) == value
          end
        end

        private
        def traverse_(value, &block)
          case value
          when Array
            value.each do |el|
              traverse_ el, &block
            end
          when Node
            block[value]
            value.traverse(&block)
          end
        end
      end

      def self.def_node(superclass, *attrs, &block)
        unless superclass <= Node
          raise ArgumentError, 'superclass must be kind of Node'
        end

        Class.new superclass do
          self.attrs *attrs
          class_eval(&block) if block
        end
      end
    end
  end
end
