require 'net/ldap'
require 'net/ldap/password'

module FTPrs
  module Server
    class LDAPConnection
      attr_accessor :config
      
      def initialize(config)
        @config = config
        @config[:ldap][:auth][:method] = @config[:ldap][:auth][:method].to_sym
        unless @config[:ldap][:encryption].nil?
           @config[:ldap][:encryption] = @config[:ldap][:encryption].to_sym
        end
        @ds = Net::LDAP.new(@config[:ldap])
        if (ENV['RACK_ENV'] == "production")
          @lh = File.new([@config[:env][:log], "/ldap.log"].join, "a+")
          @lh.sync = true
        else
          @lh = $stdout
        end
      end
      
      def log(msg)
        @lh.puts msg
      end
      
      def crypt(password)
        characters = [ ("A" .. "Z").to_a, ("a" .. "z").to_a, (0 .. 9).to_a, ".", "/" ].flatten
        salt = ""
        1.upto(4) { |index| salt = [salt, characters[rand(characters.length)].to_s].join }
        encrypt = ["{CRYPT}", password.crypt(salt)].join
        return encrypt
      end
      
      def set_password(user, dn, password)
        ops = [
          [:replace, :userpassword, [crypt(password)]]
        ]
        log("#{user[:name]} #{user[:ip]} operation replace password \"#{password}\" for #{dn}")
        ret = {
          :status => 1,
          :message => "Success",
          :values => ""
        }
        #return @ds.modify(:dn => dn, :operations => ops)
        #ret = @ds.get_operation_result
        return ret
      end
      
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