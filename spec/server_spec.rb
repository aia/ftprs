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
        :log => 'ftprs/log',
        :static  => 'lib/ftprs/server/http/static',
        :templates => 'lib/ftprs/server/http/templates'
      }
    }
    FTPrs::Server::LDAPConnection.stub(:new).and_return(mock(FTPrs::Server::LDAPConnection))
  end
  
  it "should load configuration" do
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
    custom_output = StringIO.new
    $stdout = custom_output
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
