require 'sinatra/base'
require 'json'
require 'net/ldap'
require 'erb'


module FTPrs
  module Server
    
    #
    # Sinatra application
    #
    class HTTPConnection < Sinatra::Base
      
      before do
        @header_template = {
          :pages => ["list", "new", "edit"],
          :active => "new"
        }
        @result_template = {
          :lines => []
        }
      end
      
      # HTTP GET /
      # @method / 
      # @return [GET] Redirect to /ftprs/users/new
      get '/' do
        redirect '/ftprs/users/new'
      end
      
      # HTTP GET /ftprs/users/list
      # @method /ftprs/users/list
      # @return [GET] Returns the frame for the list of LDAP/FTP users
      get '/ftprs/users/list' do
        @header_template[:active] = "list"
        erb :ftpusers
      end
      
      # HTTP GET /ftprs/users/list/json
      # @method /ftprs/users/list/json
      # @return [GET] Returns the list of LDAP/FTP users as a JSON Object
      get '/ftprs/users/list/json' do
        list_ftp_users
      end
      
      # HTTP GET /ftprs/users/new
      # @method /ftprs/users/new
      # @return [GET] Returns the form for a new LDAP/FTP users
      get '/ftprs/users/new' do
        @header_template[:active] = "new"
        erb :ftpnew
      end
      
      # HTTP POST /ftprs/users/new
      # @method /ftprs/users/new
      # @return [POST] Returns the result of the add new user operation
      post '/ftprs/users/new' do
        @header_template[:active] = "new"
        @result_template[:heading] = "Creating a new user - #{params[:username]}"
        
        next_uid = get_next_uid
        
        if (next_uid[:status] == 0)
          @result_template[:lines] << "Failed to acquire next UID" << next_uid[:message]
          return erb :ftpresult
        end
        
        next_uid[:values] += 1
        FTPrs::Server.cache.set("next_uid", next_uid, :expires_in => FTPrs::Server.config[:cache][:ttl].to_i)
        pp ["cache_set", next_uid]
        
        @result_template[:lines] << "With attributes:"
        params.each_key do |key|
          @result_template[:lines] << "#{key} - #{params[key]}"
        end
        pp ["params", params]
        
        params[:uid] = next_uid[:values].to_i
        params[:sid] = params[:uid]*2 + 1000
        params[:passwd] = FTPrs::Server.ldap.crypt(params[:password])
        pp ["params", params]
        
        ldap_object = {}
        ldap_result = {}
        requestor = { :name => request.env["REMOTE_USER"], :ip => request.env["REMOTE_ADDR"] }
        
        FTPrs::Server.config[:templates].each_key do |key|
          ldap_object[key] = JSON.parse(
            FTPrs::Server.config[:templates][key].result(binding), 
            :symbolize_names => true
          )
          pp ["ldap_object", ldap_object[key]]
          ldap_result[key] = FTPrs::Server.ldap.add(requestor, ldap_object[key][:dn], ldap_object[key][:attributes])
          if (ldap_result[key][:status] == 0)
            @result_template << "" << "Adding #{key} failed" << ldap_result[:message]
            FTPrs::Server.cache.delete("next_uid")
            return erb :ftpresult
          end
        end
        
        # if (!File.exists?("/data/ftp/home/#{params[:username]}"))
        #   puts "Creating"
        #   #Dir.mkdir("/data/ftp/home/#{params[:username]}", 755)
        #   #FileUtils.chown("#{params[:username]}", "ftpadm", "/data/ftp/home/#{params[:username]}")
        # elsif (File.directory?("/data/ftp/home/#{params[:username]}"))
        #   puts "Directory exits"
        # else
        #   puts "Directory does not exist, but file exists"
        # end
        
        erb :ftpresult
      end
      
      # HTTP GET /ftprs/users/edit
      # @method /ftprs/users/edit
      # @return [GET] Returns the LDAP/FTP user edit form
      get '/ftprs/users/edit' do
        @header_template[:active] = "edit"
        erb :ftpedit
      end
      
      # HTTP POST /ftprs/users/edit
      # @method /ftprs/users/edit
      # @return [POST] Redirects to /ftprs/users/edit/:postuid page
      post '/ftprs/users/edit' do
        redirect "/ftprs/users/edit/#{params[:postuid]}"
      end
      
      # HTTP POST /ftprs/users/edit/:postuid
      # @method /ftprs/users/edit/:postuid
      # @return [POST] Returns the results of edit user parameters operation
      post '/ftprs/users/edit/:postuid' do
        @header_template[:active] = "edit"
        @result_template[:heading] = "Editing LDAP record for uid: #{params[:postuid]}"
        
        filter = Net::LDAP::Filter.eq("uidNumber", params[:postuid])
        search_rows = FTPrs::Server.ldap.search("#{FTPrs::Server.config[:ldap][:basedn]}", filter)
        
        if (search_rows[:status] == 0)
          @result_template[:lines] << "Failed to find UID" << search_rows[:message]
          return erb :ftpresult
        end
        
        @user = search_rows[:values].first
        @updated_user = {}
        pp ["user", @user]
        dn = "cn=#{params[:cn]},#{FTPrs::Server.config[:ldap][:basedn]}"
        operations = []
        params.each_key do |key|
          if (key == "postuid")
            next
          end
          @updated_user[key.to_sym] = params[key]
          if (@user[key].first != params[key])
            @result_template[:lines] << "Changed #{key} to #{params[key]}"
            operations << [:replace, key.to_sym, [params[key]]]
          end
        end
        
        @updated_user[:userpassword] = @user[:userpassword]
        pp ["updating value", "uid=#{params[:uidnumber]},#{FTPrs::Server.config[:ldap][:basedn]}"]
        pp ["updating cache", @updated_user]
        FTPrs::Server.cache.set(
          "uid=#{params[:uidnumber]},#{FTPrs::Server.config[:ldap][:basedn]}",
          @updated_user,
          :expires_in => FTPrs::Server.config[:cache][:ttl].to_i
        )
        
        requestor = { :name => request.env["REMOTE_USER"], :ip => request.env["REMOTE_ADDR"] }
        result = FTPrs::Server.ldap.modify(requestor, dn, operations)
        @result_template[:lines] << ""
        if (result[:status] == 1)
          @result_template[:lines] << "Changes were made successfully"
        else
          @result_template[:lines] << "Changes failed" << result[:message]
          FTPrs::Server.cache.delete("uid=#{params[:uidnumber]},#{FTPrs::Server.config[:ldap][:basedn]}")
        end
        
        erb :ftpresult
      end
      
      # HTTP GET /ftprs/users/edit/:postuid
      # @method /ftprs/users/edit/:postuid
      # @return [GET] Returns the LDAP/FTP user edit form filled with the specific user parameters
      get '/ftprs/users/edit/:postuid' do
        @header_template[:active] = "edit"
        
        @user = FTPrs::Server.cache.get("uid=#{params[:postuid]},#{FTPrs::Server.config[:ldap][:basedn]}")
        
        if (!@user.nil?)
          pp ["status", "cache hit"]
          pp ["user", @user]
          return erb :ftpedituid
        end
        
        pp ["status", "cache miss"]
        
        filter = Net::LDAP::Filter.eq("uidNumber", params[:postuid])
        search_rows = FTPrs::Server.ldap.search("#{FTPrs::Server.config[:ldap][:basedn]}", filter)
        
        if (search_rows[:status] == 0)
          @result_template[:heading] = "Editing UID #{params[:postuid]}"
          @result_template[:lines] = search_rows[:message]
          return erb :ftpresult
        end
        
        @user = {}
        search_rows[:values].first.each do |key, value|
          unless (key == :objectclass)
            @user[key] = value.first
          end
        end
        
        pp @user
        
        FTPrs::Server.cache.set(
          "uid=#{params[:postuid]},#{FTPrs::Server.config[:ldap][:basedn]}",
          @user,
          :expires_in => FTPrs::Server.config[:cache][:ttl].to_i
        )
        
        erb :ftpedituid
      end
      
      # HTTP GET /ftprs/users/passwd/:cn
      # @method /ftprs/users/passwd/:cn
      # @return [GET] Returns the password change form
      get '/ftprs/users/passwd/:cn' do
        erb :ftppasswd
      end
      
      # HTTP POST /ftprs/users/passwd/:cn
      # @method /ftprs/users/passwd/:cn
      # @return [POST] Returns the results of the password change operation
      post '/ftprs/users/passwd/:cn' do
        @header_template[:active] = "edit"
        @result_template[:heading] = "Changing password for User #{params[:cn]}"
        if (params[:password1] == params[:password2])
          dn = "cn=#{params[:cn]},#{FTPrs::Server.config[:ldap][:basedn]}"
          user = { :name => request.env["REMOTE_USER"], :ip => request.env["REMOTE_ADDR"] }
          status = FTPrs::Server.ldap.set_password(user, dn, params[:password2])
          if (status)
            @result_template[:lines] << "Password successfully changed"
          else
            @result_template[:lines] << "Password change faild"
          end
        else
          @result_template[:lines] << "Entered passwords did not match"
        end
        erb :ftpresult
      end
      
      # List LDAP/FTP users
      # 
      # @return [Hash] Returns the list of LDAP/FTP users
      # @private
      def list_ftp_users
        rows = FTPrs::Server.cache.get("#{FTPrs::Server.config[:ldap][:basedn]}")
        
        if (rows.nil?)
          pp ["status", "cache miss"]
          search_rows = FTPrs::Server.ldap.search("#{FTPrs::Server.config[:ldap][:basedn]}")
          if (search_rows[:status] != 0)
            rows = search_rows[:values]
            rows.map! do |entry| 
              [
                entry[:cn],
                entry[:uidNumber],
                entry[:homedirectory],
                entry[:loginshell],
                "<a href='/ftprs/users/edit/#{entry[:uidNumber].first}'>edit</a>"
              ] 
            end
            FTPrs::Server.cache.set(
              "#{FTPrs::Server.config[:ldap][:basedn]}",
              rows,
              :expires_in => FTPrs::Server.config[:cache][:ttl].to_i
            )
          else
            rows = [["", "", search_rows[:message], "", ""]]
          end
        else
          pp ["status", "cache hit"]
        end
        
        
        hash = {
          :aaData => rows
        }
        
        "#{hash.to_json}"
      end
      
      # Get next UID value from either Memcache or LDAP
      #
      # @return [Hash] an LDAP-style result hash with next_uid in :values
      def get_next_uid
        # Try to get the next UID from cache
        next_uid = FTPrs::Server.cache.get("next_uid")
        pp ["cache_get", next_uid]
        
        # For a cache miss
        if (next_uid.nil?)
          pp ["status", "cache miss"]
          # Get the next UID from LDAP
          next_uid = FTPrs::Server.ldap.find_uid(
            "#{FTPrs::Server.config[:ldap][:basedn]}", 
            {:low => 10000, :high => 12000}
          )
          pp ["next_uid", next_uid]
        # For a cache hit
        else
          pp ["status", "cache hit"]
        end
        
        return next_uid
      end
      
      helpers do
        def partial(template, locals = nil)
          if template.is_a?(String) || template.is_a?(Symbol)
            template = ('_' + template.to_s).to_sym
          else
            locals = template
            template = template.is_a?(Array) ? 
              ('_' + template.first.class.to_s.downcase).to_sym : 
              ('_' + template.class.to_s.downcase).to_sym
          end
          if locals.is_a?(Hash)
            erb(template,{ :layout => false},locals)      
          elsif locals
            locals = [locals] unless locals.respond_to?(:inject)
            locals.inject([]) do |output, element|
              output << erb(template, {:layout=>false}, {template.to_s.delete("_").to_sym => element})
            end.join("\n")
          else 
            erb(template, {:layout => false})
          end
        end
      end
    end
  end
end