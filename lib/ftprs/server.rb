#
# FTPrs module name space
#
module FTPrs
  #
  # FTPrs Server module
  #
  module Server
    extend self
    
    # @return [Hash] configuration handler
    attr_accessor :config
    
    # @return [Net::LDAP] ldap connection handler
    attr_accessor :ldap
    
    # @return [IO] log file handler
    attr_accessor :logger
    
    # @return [Cache] cache handler
    attr_accessor :cache
    
    # Load FTPrs configuration and initialize variables
    #
    # @param [Hash] config FTPrs configuration file
    def load(config)
      @config = config
      @ldap = LDAPConnection.new(@config)
      @cache = Cache.wrap(Dalli::Client.new("#{@config[:cache][:host]}:#{@config[:cache][:port]}"))
      setup_prefixes
      setup_folders
      compile_templates
    end
    
    # Start FTPrs HTTP server
    #
    def start
      setup_logger
      
      @app = Rack::Builder.new {
        use Rack::Auth::Basic, 'Restricted Area' do |username, password|
          if File.exist?(FTPrs::Server.config[:env][:auth])
            htpasswd = WEBrick::HTTPAuth::Htpasswd.new(FTPrs::Server.config[:env][:auth])
            crypted = htpasswd.get_passwd(nil, username, false)
            crypted == password.crypt(crypted) if crypted
          else
            username == 'admin' && password == 'admin'
          end
        end
        use Rack::Lint
        use Rack::Session::Pool, :key => 'ftprs.session', :expire_after => 60000
        use Rack::CommonLogger, @logger
        use Rack::ShowExceptions
        run Rack::Cascade.new([FTPrs::Server::HTTPConnection])
      }.to_app
      
      start_http_server
    end
    
    # Configure logging
    #
    # @see #load
    def setup_logger
      if (ENV['RACK_ENV'] == "production")
        @logger = File.new([@config[:env][:log], "/rack.log"].join, "a+")
        @logger.sync = true
      else
        @logger = $stdout
        @logger.sync = true
        $stderr.reopen($stdout)
      end
    end
    
    private
    
    # Convert relative file references in the configuration to absolute paths
    #
    # @see #load
    # @private
    def setup_prefixes
      root_folder = File.dirname(__FILE__).split("/")[0..-2].join("/")
      @config[:env].each do |key, value|
        unless (value =~ /^\//)
          @config[:env][key] = [root_folder, value].join("/")
        end
      end
    end
    
    # Configure Sinatra folder settings
    #
    # @see #load
    # @private
    def setup_folders
      HTTPConnection.views = @config[:env][:templates]
      HTTPConnection.public_folder = @config[:env][:static]
    end
    
    # Compile ERB templates references in the configuration
    #
    # @see #load
    # @private
    def compile_templates
      if @config[:templates].nil?
        return
      end
      
      @config[:templates].each do |key, value|
        @config[:templates][key] = ERB.new(JSON.generate(value))
      end
    end
    
    # Start HTTP server
    #
    # @see #start
    # @private
    def start_http_server
      case @config[:http][:type] 
      when "unicorn"
        Rack::Handler::Unicorn.run(@app, @config[:http][:options])
      when "rainbows"
        Rack::Handler::Rainbows.run(@app, @config[:http][:options])
      when "thin"
        Rack::Handler::Thin.run(@app, :Port  => @config[:http][:options][:port], :Host => @config[:http][:options][:host])
      else
        Rack::Handler::WEBrick.run(@app, :Port => 4000)
      end
    end
  end
end