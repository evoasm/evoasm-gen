require 'evoasm/gen/state'
require 'evoasm/gen/c_translator'
require 'rake/tasklib'

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
      X64_TABLE_FILENAME = File.join(Evoasm::Gen.data_dir, 'tables', 'x64.csv')
      ARCH_TABLES = {
        x64: X64_TABLE_FILENAME
      }

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

            CTranslator::OUTPUT_FORMATS.each do |format|
              prereqs.concat CTranslator.template_paths(arch, format)
            end

            # pick any single file type, all are generated
            # at the same time
            target_path = gen_path(CTranslator.target_filenames(arch, :c))

            file target_path => prereqs do
              puts 'Translating'
              table = load_table arch
              unit = CUnit.new arch, table
              translator = CTranslator.new unit
              translator.translate! do |filename, content, file_type|
                next unless file_types.include? file_type
                File.write gen_path(filename), content
              end
            end

            task "translate:#{arch}" => target_path
          end

          task 'translate' => archs.map { |arch| "translate:#{arch}" }
        end

        task name => 'gen:translate'
      end

      def gen_path(filename)
        File.join @output_dir, filename
      end

      def load_table(arch)
        send :"load_#{arch}_table"
      end

      def load_x64_table
        rows = []
        File.open X64_TABLE_FILENAME do |file|
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
