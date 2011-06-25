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
  
  context 'server' do
    teardown { stop_server }
    
    context 'basic' do
      setup { start_server { |server| server.mount_proc('/ping', Proc.new { |req, resp| resp.body = 'pong' }) } }
      should('get_request_url') { assert_equal 'pong', HttpSession.get_request_url("http://localhost:#{TEST_SERVER_PORT}/ping").body }
      should('use/request') { assert_equal 'pong', HttpSession.use('localhost', false, TEST_SERVER_PORT).request('/ping').body }
      should('post_request_url') { assert_equal 'pong', HttpSession.post_request_url("http://localhost:#{TEST_SERVER_PORT}/ping", {'foo' => 'bar'}).body }
      should('use/request post') { assert_equal 'pong', HttpSession.use('localhost', false, TEST_SERVER_PORT).request('/ping', {}, :post, {'foo' => 'bar'}).body }
    end
    
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
    
  end
end
