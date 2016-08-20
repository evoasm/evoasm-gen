module Evoasm
  module Gen
    module Nodes
      class StateMachine < Node

        class << self
          def cached(unit, attrs)
            @cache ||= Hash.new { |h, k| h[k] = new *k }
            @cache[[unit, attrs]]
          end

          attr_reader :shared_variables, :local_variables, :parameters, :attributes

          private

          def params(*params)
            @parameters = params.freeze
          end

          def attrs(*attrs)
            @attributes = attrs.freeze

            @attributes.each do |attr|
              define_method attr do
                @attributes[attr]
              end

              writer_name = :"#{attr}="
              define_method writer_name do |value|
                @attributes[attr] = value
              end
              private writer_name
            end

            define_method :eql? do |other|
              @attributes == other.attributes
            end
            alias_method :==, :eql?
          end

          def local_vars(*local_vars)
            @local_variables = local_vars.freeze
          end

          def shared_vars(*shared_vars)
            @shared_variables = shared_vars.freeze
          end
        end

        def initialize(unit, attrs)
          super(unit)

          @attributes = attrs
        end

        def parameter_name?(name)
          parameters = self.class.parameters
          parameters && parameters.include?(name)
        end

        def parameters
          parameters = []
          collect_parameters root_state, parameters
        end

        private

        def collect_parameters_(arg, parameters)
        end

        def collect_parameters(state, parameters)
          state.actions.each do |action|
            action.traverse do |value|
              parameters << value if value.is_a?(ParameterConstant)
            end
          end

          state.children.each do |child, condition, _|
            collect_parameters child, parameters
            collect_parameters_ condition, parameters if condition
          end

          parameters
        end
      end

      class Instruction < StateMachine

      end
    end
  end
end
