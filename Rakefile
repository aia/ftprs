# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
#require 'rake/dsl_definition'
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "ftprs"
  gem.homepage = "http://github.com/aia/ftprs"
  gem.license = "copyright"
  gem.summary = %Q{FTPrs TDB}
  gem.description = %Q{FTPrs FTW}
  gem.email = "artem@veremey.net"
  gem.authors = ["Artem Veremey"]
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

desc "Code coverage detail"
task :coverage do
  ENV['COVERAGE'] = "true"
  Rake::Task["spec"].execute
end

#require 'rcov/rcovtask'
#desc "Code coverage brief"
#Rcov::RcovTask.new("rcov:brief") do |task|
#  task.test_files = FileList['spec/**/*_spec.rb']
#  task.rcov_opts << '--exclude /gems/,/Library/,/usr/,spec,lib/tasks'
#end

#desc "Code coverage detail"
#Rcov::RcovTask.new("rcov:detail") do |task|
#  task.test_files = FileList['spec/**/*_spec.rb']
#  task.rcov_opts << '--exclude /gems/,/Library/,/usr/,spec,lib/tasks'
#  task.rcov_opts << '--text-coverage'
#end

task :default => :spec

require 'yard'
YARD::Rake::YardocTask.new do |task|
  task.options += ["--no-private"]
end
