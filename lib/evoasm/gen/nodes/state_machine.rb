module Evoasm
  module Gen
    module Nodes
      class StateMachine < Node

        class << self
          attr_reader :shared_variables, :local_variables, :parameters

          private

          def params(*params)
            @parameters = params.freeze
          end

          def local_vars(*local_vars)
            @local_variables = local_vars.freeze
          end

          def shared_vars(*shared_vars)
            @shared_variables = shared_vars.freeze
          end
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
              parameters << value if value.is_a?(ParameterVariable)
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
