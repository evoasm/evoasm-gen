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
          @parameters ||= collect_parameters root_state, []
        end

        private

        def collect_parameters_(node, parameters)
          node.traverse do |child_node|
            if child_node.is_a?(ParameterVariable)
              parameter_name = child_node.name
              parameter = Parameter.new unit, parameter_name,
                                        child_node.domain || parameter_domain(parameter_name)
              parameters << parameter
            end
          end
        end

        def collect_parameters(state, parameters)
          state.actions.each do |action|
            collect_parameters_ action, parameters
          end

          state.children.each do |child, condition, _|
            collect_parameters_ condition, parameters if condition
            collect_parameters child, parameters
          end

          parameters
        end
      end
    end
  end
end
