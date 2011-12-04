require 'net/ldap'
require 'net/ldap/password'

module FTPrs
  module Server
    
    #
    # LDAP Connection
    #
    class LDAPConnection
      
      # @return [Hash] LDAP configuration reference
      # @private
      attr_accessor :config
      
      # Initialize LDAP connection
      #
      # @param [Hash] config LDAP configuration parameters
      #
      def initialize(config)
        # Setup configuration reference
        @config = config
        # Convert authentication method to symbol
        @config[:ldap][:auth][:method] = @config[:ldap][:auth][:method].to_sym
        # If LDAP connection is set to be encrypted
        unless @config[:ldap][:encryption].nil?
           # Convert encryption method to symbol
           @config[:ldap][:encryption] = @config[:ldap][:encryption].to_sym
        end
        # Setup LDAP connection handler
        @ds = Net::LDAP.new(@config[:ldap])
        # Configure logging for production environment
        if (ENV['RACK_ENV'] == "production")
          # Log to specified file
          @lh = File.new([@config[:env][:log], "/ldap.log"].join, "a+")
          @lh.sync = true
        # Configure logging for development environment
        else
          # Log to standard out
          @lh = $stdout
        end
      end
      
      # Log an LDAP message
      #
      # @param [String] msg Message to log
      #
      # @private
      def log(msg)
        @lh.puts msg
      end
      
      # Get a password hash
      #
      # @param [String] password Plain text password to be hashed
      # 
      # @return [String] Returns an password hash formatted for LDAP
      def crypt(password)
        characters = [ ("A" .. "Z").to_a, ("a" .. "z").to_a, (0 .. 9).to_a, ".", "/" ].flatten
        salt = ""
        1.upto(4) { |index| salt = [salt, characters[rand(characters.length)].to_s].join }
        encrypt = ["{CRYPT}", password.crypt(salt)].join
        return encrypt
      end
      
      # Change LDAP/FTP user password
      # 
      # @param [Hash] requestor An authenticated user who made the password change request
      # @param [String] dn LDAP DN for a user subject
      # @param [String] password New password in plain text
      #
      # @return [Hash] Returns a hash containing the result of the password change operation
      def set_password(requestor, dn, password)
        ops = [
          [:replace, :userpassword, [crypt(password)]]
        ]
        log("#{requestor[:name]} #{user[:ip]} operation replace password \"#{password}\" for #{dn}")
        ret = {
          :status => 1,
          :message => "Success",
          :values => ""
        }
        #return @ds.modify(:dn => dn, :operations => ops)
        #ret = @ds.get_operation_result
        return ret
      end
      
      # Search LDAP/FTP database
      # 
      # @param [String] base Base DN to be searched
      # @param [Net::LDAP::Filter] filter LDAP search filter
      # @param [String] attributes LDAP search attributes
      #
      # @return [Hash] Returns a hash containing the result of the search operation
      def search(base, filter = nil, attributes = nil)
        rows = []
        
        timeout_status = nil
        search_status = nil
        
        begin
          timeout_status = Timeout::timeout(60) do
            @ds.search(:base => base, :filter => filter, :attributes => attributes) do |entry|
              if (entry[:cn] != [])
                rows << entry
              end 
            end
            
            search_status = @ds.get_operation_result
          end
        rescue Timeout::Error => te
          ret = {
            :status => 0,
            :message => "Connection to LDAP timed out",
            :values => nil
          }
          return ret
        rescue Exception => e
          pp ["exception", e]
        end
        
        if (search_status.code == 0)
          ret = {
            :status => 1,
            :message => "Success",
            :values => rows
          }
        else
          ret = {
            :status => 0,
            :message => "Net-LDAP Error #{search_status.code}: #{search_status.message}",
            :values => nil
          }
        end
        
        return ret
      end
      
      
      # Find the next available UID in the LDAP database
      # 
      # @param [String] base Base DN to be searched
      # @param [Hash] range Range of UIDs to search
      #
      # @return [Hash] Returns a hash containing the result of the search operation
      def find_uid(base, range)
        search_rows = search(base, nil, ["cn", "uidnumber"])
        if (search_rows[:status] == 0)
          return search_rows
        else
          uids = search_rows[:values]
          uids.map! { |entry| entry[:uidnumber].first.to_i }
          selected = uids.select { |entry| ((entry < range[:high]) && (entry > range[:low])) }
          ret = {
            :status => 1,
            :message => "Success",
            :values =>selected.max.succ
          }
          return ret
        end
      end
      
      # Add an LDAP/FTP user
      # 
      # @param [Hash] requestor An authenticated user who made the add request
      # @param [String] dn LDAP DN for a user subject
      # @param [String] attributes LDAP add operation attributes
      #
      # @return [Hash] Returns a hash containing the result of the add operation
      def add(requestor, dn, attributes)
        log("#{requestor[:name]} #{requestor[:ip]} added #{dn}")
        ret = {
          :status => 1,
          :message => "Success",
          :values => ""
        }
        #@ds.add(:dn => dn, :attributes => attributes)
        #ret = @ds.get_operation_result
        return ret
      end
      
      # Modify LDAP/FTP user parameters
      # 
      # @param [Hash] requestor An authenticated user who made the modify request
      # @param [String] dn LDAP DN for a user subject
      # @param [Array] ops An array of modify operations
      #
      # @return [Hash] Returns a hash containing the result of the modify operation
      def modify(requestor, dn, ops)
        ops.each do |op|
          log("#{requestor[:name]} #{requestor[:ip]} operation #{op[0]} #{op[1]} \"#{op[2].join(', ')}\" for #{dn}")
        end
        ret = {
          :status => 1,
          :message => "Success",
          :values => ""
        }
        #@ds.modify(:dn => dn, :operations => ops)
        #ret = @ds.get_operation_result
        return ret
      end
    end
  end
end