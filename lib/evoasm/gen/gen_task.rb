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
      attr_reader :name, :archs
      attr_accessor :file_types

      ALL_ARCHS = %i(x64)
      TABLE_X64_FILENAME = File.join(Evoasm::Gen.data_dir, 'tables', 'x64.csv')
      SIMILAR_INSTRUCTIONS_X64_FILENAME = File.join(Evoasm::Gen.data_dir, 'tables', 'inst_dist_x64.yml')

      ARCH_TABLES = {
        x64: TABLE_X64_FILENAME
      }.freeze

      def initialize(name = 'evoasm:gen', output_dir, &block)
        @ruby_bindings = true
        @name = name
        @archs = ALL_ARCHS
        @output_dir = output_dir
        @file_types = %i(c h enums_h)

        block[self] if block

        define
      end

      def define
        namespace 'evoasm:gen' do
          archs.each do |arch|
            prereqs = [ARCH_TABLES[arch]]

            Translator::OUTPUT_FORMATS.each do |format|
              prereqs.concat Translator.template_paths(arch, format)
            end

            # pick any single file type, all are generated
            # at the same time
            target_path = output_path(Translator.target_filenames(arch, :c))

            file target_path => prereqs do
              puts 'Translating'
              table = load_table arch
              similar_insts = load_similar_instructions arch
              unit = Unit.new arch, table, similar_insts
              translator = Translator.new unit
              translator.translate! do |filename, content, file_type|
                next unless file_types.include? file_type
                File.write output_path(filename), content
              end
            end

            task "translate:#{arch}" => target_path
          end

          task 'translate' => archs.map { |architecture| "translate:#{architecture}" }
        end

        task name => 'gen:translate'
      end

      def output_path(filename)
        File.join @output_dir, filename
      end

      def load_table(arch)
        send :"load_table_#{arch}"
      end

      def load_similar_instructions(arch)
        send :"load_similar_instructions_#{arch}"
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
