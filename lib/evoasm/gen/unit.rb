module Evoasm
  module Gen
    class Unit
      def find_or_create_node(class_, *array, **hash)
        @nodes ||= []

        attrs = array.empty? ? hash : array

        node = @nodes.find do |node|
          node.is_a?(class_) && node.match?(attrs)
        end

        return node if node

        if attrs.is_a? Hash
          create_node class_, hash_to_attr_args(class_, attrs)
        else
          create_node class_, attrs
         end
      end

      private

      def hash_to_attr_args(class_, hash)
        attrs = []
        class_.attributes.each do |attr|
          attrs.push hash.delete attr
        end
        raise ArgumentError, "invalid attributes #{hash.keys}" unless hash.empty?
        attrs
      end

      def create_node(class_, attrs)
        node = class_.new self, *attrs
        @nodes << node
        node
      end

    end


  end
end
