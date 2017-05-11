require 'evoasm/gen/translator'
require 'rake/tasklib'
require 'yaml'

module Evoasm
  module Gen
    class GenTask < Rake::TaskLib
      include Evoasm::Gen

      HEADER_N_LINES = 15
      CSV_SEPARATOR = ','

      attr_accessor :ruby_bindings
      attr_reader :name, :modules
      attr_accessor :file_types

      ALL_MODULES = %i(x64 common)
      TABLE_X64_FILENAME = File.join(Evoasm::Gen.data_dir, 'tables', 'x64.csv')
      SIMILAR_INSTRUCTIONS_X64_FILENAME = File.join(Evoasm::Gen.data_dir, 'tables', 'inst_dist_x64.yml')

      PREREQUISITES = {
        x64: TABLE_X64_FILENAME
      }.freeze

      def initialize(name = 'evoasm:gen', output_dir, &block)
        @ruby_bindings = true
        @name = name
        @modules = ALL_MODULES
        @output_dir = output_dir
        @file_types = %i(c h enums_h)

        block[self] if block

        define
      end

      def define
        namespace 'evoasm:gen' do
          modules.each do |module_|
            prereqs = [PREREQUISITES[module_]].compact

            Translator::OUTPUT_FORMATS.each do |format|
              prereqs.concat Translator.template_paths(module_, format)
            end

            # pick any single file type, all are generated
            # at the same time
            target_path = output_path(Translator.target_filenames(module_, :h))

            file target_path => prereqs do
              puts 'Translating'
              table = load_table module_
              similar_insts = load_similar_instructions module_
              unit = Unit.new module_, table, similar_insts
              translator = Translator.new unit
              translator.translate! do |filename, content, file_type|
                next unless file_types.include? file_type
                File.write output_path(filename), content
              end
            end

            task "translate:#{module_}" => target_path
          end

          task 'translate' => modules.map { |module_| "translate:#{module_}" }
        end

        task name => 'gen:translate'
      end

      def output_path(filename)
        File.join @output_dir, filename
      end

      def load_table(arch)
        method_name = :"load_table_#{arch}"
        if respond_to? method_name
          send method_name
        end
      end

      def load_similar_instructions(arch)
        method_name = :"load_similar_instructions_#{arch}"
        if respond_to? method_name
          send method_name
        end
      end

      def load_similar_instructions_x64
        YAML.load(File.read(SIMILAR_INSTRUCTIONS_X64_FILENAME))
      end


      def load_table_x64
        rows = []
        File.open TABLE_X64_FILENAME do |file|
          file.each_line.with_index do |line, line_idx|
            # header
            next if line_idx == 0

            row = line.split(CSV_SEPARATOR)
            rows << row
          end
        end

        rows
      end
    end
  end
end
