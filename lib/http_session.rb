
require 'net/http'
require 'net/https'

class HttpSession
  
  # timeout for opening tcp/ip connection, in seconds
  OPEN_TIMEOUT      =  4
  
  # timeout for reading bytes from tcp/ip connection, in seconds
  READ_TIMEOUT      =  8
  
  # number of redirects to follow before throwing an error
  REDIRECT_LIMIT    = 10
  
  # number of times to retry, on connection errors
  RETRY_LIMIT       =  1
  
  # whether to assume to use ssl by default or not (normally should be false)
  DEFAULT_USE_SSL   = false
  
  # ssl timeout
  SSL_TIMEOUT       =  2
  
  # kind of ssl certificate verification (should be OpenSSL::SSL::VERIFY_NONE or OpenSSL::SSL::VERIFY_PEER)
  SSL_VERIFY_MODE   = OpenSSL::SSL::VERIFY_PEER
  
  # when ssl certificate verification is used, where is the certificate authority file
  # you can get one from curl here: http://curl.haxx.se/ca/cacert.pem
  SSL_CA_FILE       = ::File.expand_path('../../share/ca/cacert.pem',  __FILE__)
  
  # ssl verify depth
  SSL_VERIFY_DEPTH  =  5
  
  
  # 
  # Request handling
  # 
  
  # shortcut for parsing a full url and performing simple GET requests
  # returns Net::HTTPResponse, or raises Timeout::Error, SystemCallError, Net::ProtocolError
  def self.get_request_url(url, headers={})
    parsed = URI.parse(url)
    use(parsed.host, parsed.scheme == 'https', parsed.port).request(parsed.path + (parsed.query.nil? ? '' : "?#{parsed.query}"), headers)
  end
  
  # shortcut for parsing a full url and performing simple POST requests
  # returns Net::HTTPResponse, or raises Timeout::Error, SystemCallError, Net::ProtocolError
  def self.post_request_url(url, params, headers={})
    parsed = URI.parse(url)
    use(parsed.host, parsed.scheme == 'https', parsed.port).request(parsed.path + (parsed.query.nil? ? '' : "?#{parsed.query}"), headers, :post, params)
  end
  
  # internally handle GET and POST requests (recursively for redirects and retries)
  # returns Net::HTTPResponse, or raises Timeout::Error, SystemCallError, Net::ProtocolError
  def request(uri='/', headers={}, type=:get, post_params={}, redirect_limit=REDIRECT_LIMIT, retry_limit=RETRY_LIMIT)
    req = case type
      when :get
        Net::HTTP::Get.new(uri)
      when :post
        Net::HTTP::Post.new(uri)
      else
        raise ArgumentError, "bad type: #{type}"
    end
    headers.each { |k, v| req[k] = v } unless headers.blank?
    req['Cookie'] = cookie_string if cookies?
    req.set_form_data(post_params) if type == :post
    
    begin
      handle.start unless handle.started? # may raise Timeout::Error
      response = handle.request(req) # may raise Errno::* (subclasses of SystemCallError)
    rescue Timeout::Error, SystemCallError
      handle.finish if handle.started?
      raise if retry_limit == 0
      request(uri, headers, type, post_params, redirect_limit, retry_limit - 1)
      
    else
      add_cookies response
      if response.kind_of?(Net::HTTPRedirection)
        raise Net::HTTPError.new('Redirection limit exceeded', response)  if redirect_limit == 0
        loc = URI.parse(response['location'])
        if loc.scheme && loc.host && loc.port
          self.class.use(loc.host, loc.scheme == 'https', loc.port).request(loc.path + (loc.query.nil? ? '' : "?#{loc.query}"), headers, :get, {}, redirect_limit - 1)
        else
          request(loc.path + (loc.query.nil? ? '' : "?#{loc.query}"), headers, :get, {}, redirect_limit - 1)
        end
      else
        response.error! unless response.kind_of?(Net::HTTPOK) # raises Net::HTTP*Error/Exception (subclasses of Net::ProtocolError)
        raise Net::HTTPError.new('Document has no body', response) if response.body.nil? || response.body == ''
        response
      end
    end
  end
  
  
  # 
  # Session initialization and basic handling
  # 
  
  # store references to all currently-known session instances in here, for singleton method usage
  cattr_accessor :sessions
  self.sessions = {}
  
  # storage for open session handle, for instance method usage
  attr_accessor :handle
  
  # don't use new() directly, use singleton get() or use() instead
  def initialize(host, use_ssl, port)
    self.handle = Net::HTTP.new(host, port)
    self.handle.open_timeout    = OPEN_TIMEOUT     # seems to have no effect?
    self.handle.read_timeout    = READ_TIMEOUT     # seems to have an effect on establishing tcp connection??
    self.handle.close_on_empty_response = true     # seems to have no effect?
    if use_ssl
      self.handle.use_ssl       = true
      self.handle.ssl_timeout   = SSL_TIMEOUT
      self.handle.verify_mode   = SSL_VERIFY_MODE
      self.handle.ca_file       = SSL_CA_FILE
      self.handle.verify_depth  = SSL_VERIFY_DEPTH
    end
    self.cookies = {}
  end
  
  # just our own internal session key... (it looks like: "scheme://host:port")
  def self.key(host, use_ssl, port)
    "#{use_ssl ? 'https' : 'http'}://#{host}:#{port_or_default(port, use_ssl)}"
  end
  
  # check if a session exists yet ot not
  def self.exists?(host, use_ssl=DEFAULT_USE_SSL, port=nil)
    sessions.has_key?(key(host, use_ssl, port))
  end
  
  # get the session for the given host and port, nil if there isn't one yet
  def self.get(host, use_ssl=DEFAULT_USE_SSL, port=nil)
    sessions[key(host, use_ssl, port)]
  end
  
  # get the session for the given host and port, creating a new one if it doesn't exist
  def self.use(host, use_ssl=DEFAULT_USE_SSL, port=nil)
    key = key(host, use_ssl, port)
    sessions.has_key?(key) ? sessions[key] : (self.sessions[key] = new(host, use_ssl, port_or_default(port, use_ssl)))
  end
  
  # done with this session, close and reset it
  # but it still exists in the session storage in a dormant/empty state, so next request would easily reopen it
  def close
    handle.finish if handle.started?
    self.cookies = {}
  end
  
  # delete session from session storage (you should probably call close on it too, and set all references to nil so it gets garbage collected)
  def delete
    key = key(handle.address, handle.use_ssl?, handle.port)
    self.class.sessions.delete[key] if self.class.sessions.has_key?(key)
  end
  
  # return the given port, or defaults for ssl setting if it's nil
  def self.port_or_default(port, use_ssl)
    port.nil? ? (use_ssl ? Net::HTTP.https_default_port : Net::HTTP.http_default_port) : port
  end
  
  
  # 
  # Cookie handling
  # 
  
  # storage for cookies, for instance method usage
  attr_accessor :cookies
  
  # check if a session has any cookies or not
  def cookies?
    cookies.length > 0
  end
  
  # return all current cookies in a comma-delimited name=value string format
  def cookie_string
    cookies.collect { |name, val| "#{name}=#{val}" }.join(', ')
  end
  
  # store the cookies from the given response into the session (ignores all host/path/expires/secure/etc cookie options!)
  def add_cookies(response)
    return unless response.key?('set-cookie')
    response.get_fields('set-cookie').each do |cookie|
      (key, val) = cookie.split('; ')[0].split('=', 2)
      self.cookies[key] = val
    end
  end
  
end
