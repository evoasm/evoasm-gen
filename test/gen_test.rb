require_relative 'test_helper'
require 'tmpdir'

class Evoasm::GenTest < Minitest::Test
  def test_gen_task
    Dir.mktmpdir do |dir|
      Evoasm::Gen::GenTask.new dir do |t|
        t.output_formats = %i(c h ruby_ffi)
      end
      Rake::Task['evoasm:gen'].invoke

      assert File.exist?(File.join dir, Evoasm::Gen::Translator.target_filename(:x64, :c))
      assert File.exist?(File.join dir, Evoasm::Gen::Translator.target_filename(:x64, :h))
      assert File.exist?(File.join dir, Evoasm::Gen::Translator.target_filename(:x64, :ruby_ffi))
    end
  end
end
