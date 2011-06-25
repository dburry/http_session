require 'helper'

class TestHttpSession < Test::Unit::TestCase
  context 'simple class methods' do
    setup { @c = HttpSession }
    
    context 'key' do
      should('defaults') { assert_equal 'http://foo:80',   @c.key('foo', false, nil)  }
      should('port')     { assert_equal 'http://foo:8080', @c.key('foo', false, 8080) }
      should('ssl')      { assert_equal 'https://foo:443', @c.key('foo', true,  nil)  }
      should('ssl port') { assert_equal 'https://foo:444', @c.key('foo', true,  444)  }
    end
    
    context 'port_or_default' do
      should('defaults') { assert_equal 80,   @c.port_or_default(nil,  false) }
      should('port')     { assert_equal 8080, @c.port_or_default(8080, false) }
      should('ssl')      { assert_equal 443,  @c.port_or_default(nil,  true)  }
      should('ssl port') { assert_equal 444,  @c.port_or_default(444,  true)  }
    end
    
    context 'get' do
      setup { @i = @c.use('foo') }
      should('work')     { assert_equal @i,  @c.get('foo') }
      should('fail')     { assert_equal nil, @c.get('bar') }
      should('nossl')    { assert_equal @i,  @c.get('foo', false) }
      should('bad ssl')  { assert_equal nil, @c.get('foo', true) }
      should('port')     { assert_equal @i,  @c.get('foo', false, 80) }
      should('bad port') { assert_equal nil, @c.get('foo', false, 8080) }
    end
    
    context 'exists?' do
      setup { @i = @c.use('foo') }
      should('work')     { assert_equal true,  @c.exists?('foo') }
      should('fail')     { assert_equal false, @c.exists?('bar') }
      should('nossl')    { assert_equal true,  @c.exists?('foo', false) }
      should('bad ssl')  { assert_equal false, @c.exists?('foo', true) }
      should('port')     { assert_equal true,  @c.exists?('foo', false, 80) }
      should('bad port') { assert_equal false, @c.exists?('foo', false, 8080) }
    end
    
  end
  context 'simple instance methods' do
    setup { @c = HttpSession.new('foo', false, nil) }
    
    context 'cookies?' do
      should 'empty' do
        assert_equal false, @c.cookies?
      end
      should 'set' do
        @c.cookies['foo'] = 'bar'
        assert_equal true, @c.cookies?
      end
    end
    
    context 'cookie_string' do
      setup { @c.cookies['foo'] = 'bar' }
      should 'one' do
        assert_equal 'foo=bar', @c.cookie_string
      end
      should 'two' do
        @c.cookies['one'] = 'two'
        # splits into a set to compare because the order is not guaranteed...
        assert_equal Set.new(['foo=bar', 'one=two']), Set.new(@c.cookie_string.split(', '))
      end
    end
    
  end
  
  context 'bad request type' do
    should 'fail with message' do
      begin
        HttpSession.use('localhost', false, TEST_SERVER_PORT).request('/', {}, :foo)
      rescue ArgumentError => e
        assert_equal('bad type: foo', e.message)
      else
        fail 'nothing was raised'
      end
    end
  end
  
  context 'server' do
    teardown { stop_server }
    
    context 'basic' do
      setup { start_server { |server| server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' }) } }
      should('get_request_url') { assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/ping").body }
      should('use/request') { assert_equal 'pong', HttpSession.use('localhost', false, TEST_SERVER_PORT).request('/ping').body }
      should('post_request_url') { assert_equal 'pong', HttpSession.post_request_url("http://localhost:#{TEST_SERVER_PORT}/ping", {'foo' => 'bar'}).body }
      should('use/request post') { assert_equal 'pong', HttpSession.use('localhost', false, TEST_SERVER_PORT).request('/ping', {}, :post, {'foo' => 'bar'}).body }
      
      should 'close' do
        assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/ping").body
        sesn = HttpSession.get('localhost', false, TEST_SERVER_PORT)
        assert_not_nil sesn
        assert_equal true, sesn.handle.started?
        sesn.close
        assert_equal false, sesn.handle.started?
      end
      should 'delete' do
        assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/ping").body
        sesn = HttpSession.get('localhost', false, TEST_SERVER_PORT)
        assert_not_nil sesn
        sesn.close
        sesn.delete
        sesn = HttpSession.get('localhost', false, TEST_SERVER_PORT)
        assert_equal nil, sesn
      end
    end
    
    context 'redirect' do
      setup do
        start_server do |server|
          server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' })
          server.mount_proc('/redir', Proc.new { |req, resp| resp.set_redirect(::WEBrick::HTTPStatus::Found, "http://localhost:#{TEST_SERVER_PORT}/ping") })
        end
      end
      should('work') { assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/redir").body }
    end
    
    # context 'redirect without host' do
    #   setup do
    #     start_server do |server|
    #       server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' })
    #       # note: webrick is smart and converts this to a properly-formed redirect with http://host:port
    #       # and it does it if I set the headers directly too... so there doesn't seem to be any way to
    #       # exercise our bad-webserver-redirect-handling code using webrick...
    #       server.mount_proc('/redir', Proc.new { |req, resp| resp.set_redirect(::WEBrick::HTTPStatus::Found, "/ping") })
    #     end
    #   end
    #   should('work') { assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/redir").body }
    # end
    
    context 'redirect 10x' do
      setup do
        start_server do |server|
          redircount = 0
          server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' })
          server.mount_proc('/redir', Proc.new { |req, resp|
            where = redircount < 9 ? 'redir' : 'ping' # add one for the last redirect to the ping
            redircount += 1
            resp.set_redirect(::WEBrick::HTTPStatus::Found, "http://localhost:#{TEST_SERVER_PORT}/#{where}")
          })
        end
      end
      should('work') { assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/redir").body }
    end
    
    context 'redirect 11x' do
      setup do
        start_server do |server|
          redircount = 0
          server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' })
          server.mount_proc('/redir', Proc.new { |req, resp|
            where = ((redircount < 10) ? 'redir' : 'ping')
            redircount += 1
            resp.set_redirect(::WEBrick::HTTPStatus::Found, "http://localhost:#{TEST_SERVER_PORT}/#{where}")
          })
        end
      end
      # should 'fail'  do
      #   assert_raise(Net::HTTPError) do
      #     HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/redir")
      #   end
      # end
      # assert_raise can only check instance, not message... so we do this much longer thing instead:
      should 'fail with message' do
        begin
          HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/redir")
        rescue Net::HTTPError => e
          assert_equal('Redirection limit exceeded', e.message)
        else
          fail 'nothing was raised'
        end
      end
    end
    
    context 'sent cookie' do
      setup do
        start_server do |server|
          server.mount_proc('/ping', Proc.new { |req, resp|
            resp.cookies << ::WEBrick::Cookie.new('foo', 'bar')
            resp.body = 'pong'
          })
        end
      end
      should 'be received' do
        assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/ping").body
        assert_equal 'bar',  HttpSession.get('localhost', false, TEST_SERVER_PORT).cookies['foo']
      end
    end
    
    context 'sent/expected cookie' do
      setup do
        start_server do |server|
          # set a cookie when you go to /get
          server.mount_proc('/get', Proc.new { |req, resp|
            resp.cookies << ::WEBrick::Cookie.new('foo', 'bar')
            resp.body = 'hereyago'
          })
          # check if the cookie was sent back when you go to /check, and return 'set' or 'BAD' in the body indicating
          server.mount_proc('/check', Proc.new { |req, resp|
            resp.body = req.cookies[0].name == 'foo' && req.cookies[0].value == 'bar' ? 'set' : 'BAD'
          })
        end
      end
      should 'be received and sent back' do
        assert_equal 'hereyago', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/get").body
        assert_equal 'set',      HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/check").body
      end
    end
    
    # TODO: test SSL!
    # TODO: test retry_limit
    # TODO: test keepalives!
  end
end
