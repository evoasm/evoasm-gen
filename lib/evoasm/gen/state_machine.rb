module Evoasm
  module Gen
    class StateMachine
      def self.find_or_create(attrs)
        @cache ||= Hash.new { |h, k| h[k] = new k}
        @cache[attrs]
      end

      def initialize(attrs)
        attrs.each do |k, v|
          # make sure there is a reader defined
          raise unless respond_to? k
          instance_variable_set :"@#{k}", v
        end
      end
    end
  end
end
