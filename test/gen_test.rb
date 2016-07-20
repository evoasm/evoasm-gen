require_relative 'test_helper'
require 'tmpdir'

class Evoasm::GenTest < Minitest::Test
  def test_gen_task
    Dir.mktmpdir do |dir|
      Evoasm::Gen::GenTask.new dir do |t|
        t.file_types = %i(c h ruby_ffi)
      end
      Rake::Task['evoasm:gen'].invoke

      translator = Evoasm::Gen::Translator

      translator.target_filenames(:x64, :c).each do |f|
        assert File.exist?(File.join dir, f)
      end

      translator.target_filenames(:x64, :h).each do |f|
        assert File.exist?(File.join dir, f)
      end

      translator.target_filenames(:x64, :ruby_ffi).each do |f|
        assert File.exist?(File.join dir, f)
      end
    end
  end
end
