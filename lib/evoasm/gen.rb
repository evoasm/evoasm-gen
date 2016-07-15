require 'evoasm/gen/version'

module Evoasm
  module Gen
    def self.root_dir
      File.expand_path File.join(__dir__, '..', '..')
    end

    def self.data_dir
      File.join root_dir, 'data'
    end
  end
end

require 'evoasm/gen/gen_task'
