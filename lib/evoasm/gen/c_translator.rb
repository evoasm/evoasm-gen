require 'erubis'
require 'evoasm/gen/core_ext/string_io'
require 'evoasm/gen/c_unit'
require 'evoasm/gen/x64'

module Evoasm
  module Gen

    class CTranslator
      include NameUtil

      attr_reader :unit

      OUTPUT_FORMATS = %i(c h ruby_ffi)

      def self.target_filenames(architecture, file_type)
        case architecture
        when :x64
          case file_type
          when :c
            %w(evoasm-x64-insts.c evoasm-x64-misc.c)
          when :h
            %w(evoasm-x64-insts.h evoasm-x64-enums.h evoasm-x64-misc.h)
          when :ruby_ffi
            %w(x64_enums.rb)
          else
            raise "invalid file type #{file_type}"
          end
        else
          raise "invalid architecture #{architecture}"
        end
      end

      def self.templates_dir
        File.join Evoasm::Gen.data_dir, 'templates'
      end

      def self.template_path(filename)
        File.join templates_dir, "#{filename}.erb"
      end

      def self.template_paths(architecture, output_type)
        target_filenames(architecture, output_type).map do |target_filename|
          File.join templates_dir, "#{target_filename}.erb"
        end
      end

      def initialize(unit)
        @unit = unit
      end

      def translate!(&block)
        render_templates(:c, binding, &block)
        render_templates(:h, binding, &block)
        render_templates(:ruby_ffi, binding, &block)
      end

      def architecture
        unit.architecture
      end

      private

      def render_templates(file_type, binding, &block)
        target_filenames = self.class.target_filenames(architecture, file_type)

        target_filenames.each do |target_filename|
          template_path = self.class.template_path(target_filename)
          renderer = Erubis::Eruby.new(File.read(template_path))
          block[target_filename, renderer.result(binding), file_type]
        end
      end
    end
  end
end
