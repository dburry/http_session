# encoding: utf-8

# like printing `rvm current` only it actually works in `rvm version,version,version rake some:task`
puts "\n*** Using #{File.basename(ENV['GEM_HOME'])}" if ENV.has_key?('GEM_HOME')

# for some odd reason, requiring bundler causes rake and jeweler to do recursive requires on ruby 1.9.2...
# therefore the following is all commented out for now...
# bundler is still used in development, just use it on the command line to make a clean rvm gemset (or use rubies:* tasks)
# instead of this enforcing the gems at rake run time

# require 'rubygems'
# require 'bundler'
# begin
#   Bundler.require(:default, :development)
# rescue Bundler::BundlerError => e
#   $stderr.puts e.message
#   $stderr.puts "Run `bundle install` to install missing gems"
#   exit e.status_code
# end
require 'rake'


begin
  require 'jeweler'
rescue LoadError
  puts 'WARNING: missing jeweler library, some tasks are not available'
else
  Jeweler::Tasks.new do |gem|
    # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
    gem.name = "http_session"
    gem.homepage = "http://github.com/dburry/http_session"
    gem.license = "MIT"
    gem.summary = %Q{A useful yet still extremely light-weight web client built on top of Ruby Net::HTTP}
    gem.email = "dburry@falcon"
    gem.authors = ["David Burry"]
    # dependencies defined in Gemfile
  end
  Jeweler::RubygemsDotOrgTasks.new
end

begin
  require 'rake/testtask'
rescue LoadError
  puts 'WARNING: missing test library, some tasks are not available'
else
  task :default => :test
  Rake::TestTask.new(:test) do |test|
    test.libs << 'lib' << 'test'
    test.pattern = 'test/**/test_*.rb'
    # test.verbose = true
  end
end

if RUBY_VERSION =~ /^1\.8\./
  begin
    require 'rcov/rcovtask'
  rescue LoadError
    puts 'WARNING: missing rcov library, some tasks are not available'
  else
    Rcov::RcovTask.new do |test|
      test.libs << 'test'
      test.pattern = 'test/**/test_*.rb'
      # test.verbose = true
      test.rcov_opts << '--exclude "gems/*"'
    end
  end
end

if RUBY_VERSION =~ /^1\.9/
  begin
    require 'rdoc/task'
  rescue LoadError
    puts 'WARNING: missing rdoc library, some tasks are not available'
  else
    RDoc::Task.new do |rdoc|
      version = File.exist?('VERSION') ? File.read('VERSION') : ""
      rdoc.rdoc_dir = 'rdoc'
      rdoc.title = "http_session #{version}"
      rdoc.rdoc_files.include('README*')
      rdoc.rdoc_files.include('lib/**/*.rb')
    end
  end
end

if `which rvm`.empty?
  puts 'WARNING: missing rvm executable, some tasks are not available'
else
  task :rubies => 'rubies:list'
  namespace :rubies do
    @@ruby_versions = [
      # edit this list to test on more rubies...
      # though beware that some development dependencies might be troublesome on some versions...
      'ruby-1.9.2-p180',
      'ruby-1.9.1-p378',
      'ruby-1.8.7-p330',
      'ruby-1.8.6-p399'
    ]
    def installed_ruby_versions
      current_rubies = `rvm list`
      ruby_version_gemsets_string = @@ruby_versions.select { |r| current_rubies =~ /\b#{r}\b/ }
    end
    def missing_ruby_versions
      current_rubies = `rvm list`
      ruby_version_gemsets_string = @@ruby_versions.select { |r| current_rubies !~ /\b#{r}\b/ }
    end
    desc "List all the versions of Ruby these tasks use"
    task :list do
      puts 'The following Ruby versions are used in testing:'
      @@ruby_versions.each { |r| puts r }
    end
    desc "Setup multiple versions of Ruby for testing, and populate an RVM gemset for each"
    task :setup do
      missing = missing_ruby_versions
      system "rvm install #{missing.join(',')}" unless missing.empty?
      ruby_version_gemsets_string = @@ruby_versions.collect { |r| r + '@http_session' }.join(',')
      system "rvm --create #{ruby_version_gemsets_string} gem install bundler"
      system "rvm #{ruby_version_gemsets_string} exec bundle install"
    end
    desc "Remove RVM gemsets (leave the Ruby versions installed though)"
    task :cleanup do
      installed_ruby_versions.each { |r| system "rvm --force #{r} gemset delete http_session" }
    end
    desc "Run tests on multiple versions of Ruby, using RVM"
    task :test do
      installed = installed_ruby_versions
      puts "WARNING: some rubies are missing from RVM, run `rake rubies:setup` to install them" if installed != @@ruby_versions
      ruby_version_gemsets_string = installed.collect { |r| r + '@http_session' }.join(',')
      system "rvm #{ruby_version_gemsets_string} exec rake test"
    end
  end
end
