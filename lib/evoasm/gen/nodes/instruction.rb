require 'evoasm/gen/nodes/state_machine'

module Evoasm
  module Gen
    module Nodes
      class Instruction < Node
        def parameters(basic: false)
          if basic
            return nil unless basic?
            return @basic_parameters if @basic_parameters
          else
            return @parameters if @parameters
          end

          parameter_variables =
            if basic
              basic_state_machine.parameter_variables
            else
              state_machine.parameter_variables
            end

          parameters = parameter_variables.map do |parameter_variable|
            next if parameter_variable.name.nil?

            Parameter.new unit, parameter_variable.name,
                          parameter_variable.domain || parameter_domain(parameter_variable.name),
                          parameter_variable.undefinedable?
          end.compact

          if basic
            @basic_parameters = parameters
          else
            @parameters = parameters
          end
        end
      end
    end
  end
end

