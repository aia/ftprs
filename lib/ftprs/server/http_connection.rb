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
        erb :ftpnew
      end
      
      # HTTP POST /ftprs/users/new
      # @method /ftprs/users/new
      # @return [POST] Returns the result of the add new user operation
      post '/ftprs/users/new' do
        # Try to get the next UID from cache
        rows = FTPrs::Server.cache.get("next_uid")
        pp ["cache_get", rows]
        
        # For a cache miss
        if (rows.nil?)
          pp ["status", "cache miss"]
          # Get the next UID from LDAP
          search_rows = FTPrs::Server.ldap.find_uid("#{FTPrs::Server.config[:ldap][:basedn]}", {:low => 10000, :high => 12000})
          pp ["search_rows", search_rows]
        # For a cache hit
        else
          pp ["status", "cache hit"]
          # Create an LDAP-style return value
          search_rows = {
            :status => 1,
            :message => "Success",
            # Increament the cached UID
            :values => rows.to_i.succ
          }
        end
        
        # If cache or LDAP request was not successful
        if (search_rows[:status] == 0)
          @message = "<h2>#{search_rows[:message]}</h2>"
          return erb :ftpresult
        end
        
        # If cache or LDAP request was successful
        # Update the UID key in cache
        FTPrs::Server.cache.set("next_uid", search_rows[:values], :expires_in => FTPrs::Server.config[:cache][:ttl].to_i)
        pp ["cache_set", search_rows[:values]]
        
        # Prepare the message sent back to client
        @message = "<h2>Creating a new user - #{params[:username]}</h2>\nWith attributes:<br />\n"
        params.each_key do |key|
          @message = [@message, "#{key} - #{params[key]}<br />"].join("\n")
        end
        pp ["params", params]
        
        # Update the params Hash with UID, SID, and password hash
        params[:uid] = search_rows[:values].to_i
        params[:sid] = params[:uid]*2 + 1000
        params[:passwd] = FTPrs::Server.ldap.crypt(params[:password])
        pp ["params", params]
        
        ldap_object = {}
        ldap_result = {}
        # Build the requestor Hash to be sent with the LDAP add request
        requestor = { :name => request.env["REMOTE_USER"], :ip => request.env["REMOTE_ADDR"] }
        
        # For each template configured
        FTPrs::Server.config[:templates].each_key do |key|
          # Run ERB templates and build the user, group, and netgroup objects for addition to LDAP
          ldap_object[key] = JSON.parse(
            FTPrs::Server.config[:templates][key].result(binding), 
            :symbolize_names => true
          )
          pp ["ldap_object", ldap_object[key]]
          # Run the LDAP add request for the current object
          ldap_result[key] = FTPrs::Server.ldap.add(requestor, ldap_object[key][:dn], ldap_object[key][:attributes])
          # If an LDAP operation failed
          if (ldap_result[key][:status] == 0)
            # Update the message to the client
            @message = [@message, "<br /><br />Adding #{key} <u>failed</u><br />#{result[:message]}<br />"].join("\n")
            # Delete the cached UID
            FTPrs::Server.cache.delete("next_uid")
            # Done
            return erb :ftpresult
          end
        end
        
        if (!File.exists?("/data/ftp/home/#{params[:username]}"))
          puts "Creating"
          #Dir.mkdir("/data/ftp/home/#{params[:username]}", 755)
          #FileUtils.chown("#{params[:username]}", "ftpadm", "/data/ftp/home/#{params[:username]}")
        elsif (File.directory?("/data/ftp/home/#{params[:username]}"))
          puts "Directory exits"
        else
          puts "Directory does not exist, but file exists"
        end
        
        erb :ftpresult
      end
      
      # HTTP GET /ftprs/users/edit
      # @method /ftprs/users/edit
      # @return [GET] Returns the LDAP/FTP user edit form
      get '/ftprs/users/edit' do
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
        pp ["params", params]
        filter = Net::LDAP::Filter.eq("uidNumber", params[:postuid])
        search_rows = FTPrs::Server.ldap.search("#{FTPrs::Server.config[:ldap][:basedn]}", filter)
        
        if (search_rows[:status] == 0)
          @message = "<h2>#{search_rows[:message]}</h2>"
        else
          @user = search_rows[:values].first
          @updated_user = {}
          pp ["user", @user]
          dn = "cn=#{params[:cn]},#{FTPrs::Server.config[:ldap][:basedn]}"
          operations = []
          @message = "<h2>Editing LDAP record for uid: #{params[:postuid]}</h2>"
          #pp params
          params.each_key do |key|
            if (key == "postuid")
              next
            end
            @updated_user[key.to_sym] = params[key]
            if (@user[key].first != params[key])
              @message = [@message, "Changed #{key} to #{params[key]}<br />"].join("\n")
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
          if (result[:status] == 1)
            @message = [@message, "<br /><br />Changes were made <u>successfully</u><br />"].join("\n")
          else
            @message = [@message, "<br /><br />Changes <u>failed</u><br />#{result[:message]}<br />"].join("\n")
            FTPrs::Server.cache.delete("uid=#{params[:uidnumber]},#{FTPrs::Server.config[:ldap][:basedn]}")
          end
        end
        
        erb :ftpresult
      end
      
      # HTTP GET /ftprs/users/edit/:postuid
      # @method /ftprs/users/edit/:postuid
      # @return [GET] Returns the LDAP/FTP user edit form filled with the specific user parameters
      get '/ftprs/users/edit/:postuid' do
        rows = FTPrs::Server.cache.get("uid=#{params[:postuid]},#{FTPrs::Server.config[:ldap][:basedn]}")
        
        if (rows.nil?)
          pp ["status", "cache miss"]
          
          filter = Net::LDAP::Filter.eq("uidNumber", params[:postuid])
          
          search_rows = FTPrs::Server.ldap.search("#{FTPrs::Server.config[:ldap][:basedn]}", filter)
          
          if (search_rows[:status] == 0)
            @message = "<h2>#{search_rows[:message]}</h2>"
            erb :ftpresult
          else
            @user = {}
            @user_lookup = search_rows[:values].first
            @user_lookup.each do |key, value|
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
        else
          pp ["status", "cache hit"]
          @user = rows
          pp ["dn", "uid=#{params[:uid]},#{FTPrs::Server.config[:ldap][:basedn]}"]
          pp ["user", @user]
          erb :ftpedituid
        end
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
        @message = ""
        if (params[:password1] == params[:password2])
          dn = "cn=#{params[:cn]},#{FTPrs::Server.config[:ldap][:basedn]}"
          user = { :name => request.env["REMOTE_USER"], :ip => request.env["REMOTE_ADDR"] }
          status = FTPrs::Server.ldap.set_password(user, dn, params[:password2])
          if (status)
            @message = "<h2>Successfully changed password for user #{params[:cn]}</h2>"
          else
            @message = "<h2>Failed to change password for user #{params[:cn]}</h2>"
          end
        else
          @message = "<h2>Passwords did not match for user #{params[:cn]}</h2>"
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
    end
  end
end