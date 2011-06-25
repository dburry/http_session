require 'rubygems'

# require 'bundler'
# begin
#   Bundler.setup(:default, :development)
# rescue Bundler::BundlerError => e
#   $stderr.puts e.message
#   $stderr.puts "Run `bundle install` to install missing gems"
#   exit e.status_code
# end

if ENV.has_key?('USE_SIMPLECOV')
  require 'simplecov'
  SimpleCov.start do
    add_group 'Libraries', 'lib'
  end
end

require 'test/unit'
begin
  require 'shoulda'
rescue LoadError
  puts 'WARNING: missing shoulda library, cannot continue run tests'
  exit
end

require 'webrick'
require 'webrick/https'
require 'openssl'
require 'thread'
TEST_SERVER_PORT = 8081

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'http_session'

class Test::Unit::TestCase
  
  # start a simple webrick server that runs the given servlet and other options for testing
  @wbthread = nil
  def start_server(use_ssl=false, config={})
    # always run on this port
    config.update(:Port => TEST_SERVER_PORT)
    # for debugging the server itself, log debug output to stderr
    # config.update(:Logger => ::WEBrick::Log.new($stderr, ::WEBrick::Log::DEBUG))
    # or squelch all server logging for normal use
    config.update(:Logger => ::WEBrick::Log.new('/dev/null'))
    config.update(:AccessLog => [ [ File.open('/dev/null', 'w'), ::WEBrick::AccessLog::COMBINED_LOG_FORMAT ] ])
    # don't ever process any requests in parallel, always run each test one at a time
    config.update(:MaxClients => 1)
    
    if use_ssl
      # configure server to run with SSL
      config.update(:SSLEnable => true)
      config.update(:SSLVerifyClient => ::OpenSSL::SSL::VERIFY_NONE)
      config.update(:SSLCertificate => ::OpenSSL::X509::Certificate.new(File.open(File.expand_path('../ssl/server.crt',  __FILE__)).read))
      config.update(:SSLPrivateKey => ::OpenSSL::PKey::RSA.new(File.open(File.expand_path('../ssl/server.key',  __FILE__)).read))
      config.update(:SSLCertName => [ [ "CN", 'localhost' ] ])
    end
    
    # create the server
    server = ::WEBrick::HTTPServer.new(config)
    yield server if block_given?
    # run the server in its own thread, setting up USR1 signal to tell it to quit
    @wbthread = Thread.new(server) do |server|
      trap('USR1') { server.shutdown }
      server.start
    end
  end
  
  # stop the simple webrick server
  def stop_server
    if ! @wbthread.nil? && @wbthread.alive?
      # signal server thread to quit
      Process.kill('USR1', Process.pid)
      # wait for it to actually quit
      # note: Sometimes it appears to hang here at this join, when there's something wrong with the server or client
      # when that happens just comment out to see more debug info what's wrong
      # you'll also get some spurrious concurrency errors of course, but at least the problem will show up too
      @wbthread.join
    end
  end
  
end
