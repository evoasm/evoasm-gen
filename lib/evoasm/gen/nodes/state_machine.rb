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

        def parameter_variables
          @parameter_variables ||= collect_parameter_variables root_state, []
          @parameter_variables
        end

        private
        def add_parameter_variable(parameter_variables, new_parameter_variable)
          index = parameter_variables.index { |variable| variable.name == new_parameter_variable.name}
          if index
            parameter_variables[index].undefinedable =
              parameter_variables[index].undefinedable? || new_parameter_variable.undefinedable?
          else
            parameter_variables << new_parameter_variable
          end
        end

        def merge_parameter_variables(parameter_variables, new_parameter_variables)
          new_parameter_variables.each do |new_parameter_variable|
            add_parameter_variable parameter_variables, new_parameter_variable
          end
        end

        def collect_parameter_variables_(node, parameter_variables)
          node.traverse do |child_node|
            case child_node
            when ParameterVariable
              add_parameter_variable parameter_variables, child_node
            when StateMachine
              merge_parameter_variables parameter_variables, child_node.parameter_variables
            end
          end
        end

        def collect_parameter_variables(state, parameter_variables)
          state.actions.each do |action|
            collect_parameter_variables_ action, parameter_variables
          end

          state.children.each do |child, condition, _|
            collect_parameter_variables_ condition, parameter_variables if condition
            collect_parameter_variables child, parameter_variables
          end

          parameter_variables
        end
      end
    end
  end
end
