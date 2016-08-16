module Evoasm
  module Gen
    class StateMachine
      def self.find_or_create(attrs)
        @cache ||= Hash.new { |h, k| h[k] = new k}
        @cache[attrs]
      end

      def self.params(*parameters)
        return @params if parameters.empty?

        @params = parameters.freeze
      end

      def self.attrs(*attrs)
        return @attrs if attrs.empty?

        @attrs = attrs.freeze

        @attrs.each do |attr|
          define_method attr do
            @attrs[attr]
          end

          writer_name = :"#{attr}="
          define_method writer_name do |value|
            @attrs[attr] = value
          end
          private writer_name
        end

        define_method :eql? do |other|
          @attrs == other.attrs
        end
        alias_method :==, :eql?
      end

      def initialize(attrs)
        @attrs = attrs
      end

      def param_name?(name)
        parameters = self.class.params
        parameters && parameters.include?(name)
      end

      def params
        parameters = []
        collect_params root_state, parameters
      end

      private

      def collect_params_(arg, parameters)
        case arg
        when Parameter
          parameters << arg
        when Expression
          arg.args.each do |arg|
            collect_params_(arg, parameters)
          end
        when Constant
        else
          raise "unexpected class #{arg.class}"
        end
      end

      def collect_params(state, parameters)
        state.actions.each do |action|
          action.args.each do |action_arg|
            collect_params_(action_arg, parameters)
          end
        end

        state.children.each do |child, condition, _|
          collect_params child, parameters
          collect_params_ condition, parameters if condition
        end
      end

      params
    end
  end
end
