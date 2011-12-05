$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'spec_helper'

describe "FTPrs::Server" do  
  before(:each) do
    @test_config = {
      :ldap => {
        :host => "127.0.0.1",
        :port => 389,
        :base => "dc=example,dc=com",
        :auth => {
          :method => :simple,
          :username => "cn=proxyagent,ou=profile,dc=example,dc=com",
          :password => "password"
        }
      },
      :env => {
        :base => '/some/path/ftprs',
        :log => '/some/path/ftprs/log',
        :static  => '/some/path/ftprs/lib/ftprs/server/http/static',
        :templates => '/some/path/ftprs/lib/ftprs/server/http/templates'
      },
      :cache => {
        :host => "localhost",
        :port => 11211,
        :ttl => 90
      },
      :http => {
        :type => "thin",
        :options => {
          :host => "0.0.0.0",
          :port => 4000
        }
      }
    }
    FTPrs::Server::LDAPConnection.stub(:new).and_return(mock(FTPrs::Server::LDAPConnection))
    Dalli::Client.stub(:new).and_return(mock(Dalli::Client))
    Cache.stub(:wrap).and_return(mock(Cache))
  end
  
  it "should load configuration" do
    FTPrs::Server.stub(:setup_logger).and_return(true)
    FTPrs::Server.load(@test_config)
    FTPrs::Server.config.should eql(@test_config)
    FTPrs::Server::HTTPConnection.views.should eql(@test_config[:env][:templates])
    FTPrs::Server::HTTPConnection.public_folder.should eql(@test_config[:env][:static])
  end
  
  it "should setup logger for production" do
    FTPrs::Server.load(@test_config)
    ENV['RACK_ENV'] = "production"
    file_handle = mock(File)
    file_handle.should_receive(:sync=).with(true)
    File.should_receive(:new).with("/some/path/ftprs/log/rack.log", "a+").and_return(file_handle)
    FTPrs::Server.setup_logger
  end
  
  it "should setup logger for development" do
    ENV['RACK_ENV'] = "development"
    custom_output = mock(StringIO)
    custom_output.stub(:write).and_return(true)
    custom_output.should_receive(:sync=)
    custom_error = mock(StringIO)
    custom_error.stub(:write).and_return(true)
    custom_error.should_receive(:reopen)
    $stdout = custom_output
    $stderr = custom_error
    FTPrs::Server.setup_logger
    FTPrs::Server.logger.should eql(custom_output)
    
  end
  
  it "should start the server" do
    FTPrs::Server.stub(:setup_logger).and_return(true)
    Rack::Handler::Thin.stub(:run)
    FTPrs::Server.load(@test_config)
    FTPrs::Server.start
  end
end
