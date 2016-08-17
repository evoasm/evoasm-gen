require 'evoasm/gen/state'
require 'evoasm/gen/to_c/translator'
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

            Translator::OUTPUT_FORMATS.each do |format|
              prereqs.concat Translator.template_paths(arch, format)
            end

            # pick any single file type, all are generated
            # at the same time
            target_path = gen_path(Translator.target_filenames(arch, :c))

            file target_path => prereqs do
              puts 'Translating'
              insts = load_insts arch
              translator = Translator.new(arch, insts)
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

      def load_insts(arch)
        send :"load_#{arch}_insts"
      end

      def load_x64_insts
        require 'evoasm/gen/x64/instruction'

        rows = []
        File.open X64_TABLE_FILENAME do |file|
          file.each_line.with_index do |line, line_idx|
            # header
            next if line_idx == 0

            row = line.split(CSV_SEPARATOR)
            rows << row
          end
        end

        Gen::X64::Instruction.load_all(rows)
      end
    end
  end
end
