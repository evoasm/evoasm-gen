require "bundler/gem_tasks"
require "rake/testtask"
require "evoasm/gen"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test

begin
  require 'evoasm/scrapers'
  Evoasm::Scrapers::X64.new do |t|
    t.output_filename = "#{Evoasm::Gen::GenTask::X64_TABLE_FILENAME}.auto"
  end
rescue LoadError
end
