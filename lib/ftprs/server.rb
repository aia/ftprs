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
    # @private
    attr_accessor :config
    
    # @return [Net::LDAP] ldap connection handler
    # @private
    attr_accessor :ldap
    
    # @return [IO] log file handler
    # @private
    attr_accessor :logger
    
    # @return [Cache] cache handler
    # @private
    attr_accessor :cache
    
    # Load FTPrs configuration and initialize variables
    #
    # @param [Hash] config FTPrs configuration file
    #
    def load(config)
      # set @config reference
      @config = config
      
      # convert relative file references to absolute
      setup_prefixes
      
      # configure Sinatra folder settings
      setup_folders
      
      # compile ERB templates
      compile_templates
      
      # setup LDAP connection handler
      @ldap = LDAPConnection.new(@config)
      
      # setup Memcached connection handler
      cache_client = Dalli::Client.new("#{@config[:cache][:host]}:#{@config[:cache][:port]}")
      
      # wrap Memcached calls
      @cache = Cache.wrap(cache_client)
      
      pp ["ldap", @ldap]
      pp ["cache", @cache]
    end

    # Configure logging
    #
    # @see #start
    # @private
    def setup_logger
      # For production configuration
      if (ENV['RACK_ENV'] == "production")
        # Log to file
        @logger = File.new([@config[:env][:log], "/rack.log"].join, "a+")
        @logger.sync = true
      # For development configuration
      else
        # Log to standard out
        @logger = $stdout
        @logger.sync = true
        $stderr.reopen($stdout)
      end
    end
    
    # Convert relative file references in the configuration to absolute paths
    #
    # @see #load
    # @private
    def setup_prefixes
      # Determine root folder absolute path
      root_folder = File.dirname(__FILE__).split("/")[0..-2].join("/")
      @config[:env].each do |key, value|
        # If the file reference is relative
        unless (value =~ /^\//)
          # Append root folder absolute path
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
      # If no templates are specified in the configuration
      if @config[:templates].nil?
        # Done
        return
      end
      
      # For all templates configured
      @config[:templates].each do |key, value|
        # Relplace configuration JSON with an ERB object
        @config[:templates][key] = ERB.new(JSON.generate(value))
      end
    end
    
    # Start FTPrs HTTP server
    #
    def start
      # Setup logging
      setup_logger
      
      pp ["logger", @logger]
      
      # Configure a Rack application
      @app = Rack::Builder.new {
        # Configure HTTP Basic Authentication
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
        # Create distinct cookies
        use Rack::Session::Pool, :key => 'ftprs.session', :expire_after => 60000
        # Configure logger
        use Rack::CommonLogger, @logger
        use Rack::ShowExceptions
        # Ultimately dispatch requests to a Sinatra application
        run Rack::Cascade.new([FTPrs::Server::HTTPConnection])
      }.to_app
      
      # Start the configured HTTP server type
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