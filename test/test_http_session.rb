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
end
