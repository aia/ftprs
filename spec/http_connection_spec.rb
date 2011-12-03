$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'spec_helper'


describe "FTPrs::Server::HTTPConnection" do
  include Rack::Test::Methods
  
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
        :static  => 'ftprs/server/http/static',
        :templates => 'ftprs/server/http/templates'
      }
    }
    FTPrs::Server::LDAPConnection.stub(:new).and_return(mock(FTPrs::Server::LDAPConnection))
    FTPrs::Server.load(@test_config)
  end
  
  def app
    #FTPrs::Server::HTTPConnection
    Rack::Builder.new do
      use Rack::Auth::Basic, 'Restricted Area' do |username, password|
        username == 'admin' && password == 'admin'
      end
      #use Rack::Session::Pool, :key => 'ftprs.session', :expire_after => 60000
      use Rack::ShowExceptions
      use Rack::Lint
      run Rack::Cascade.new([FTPrs::Server::HTTPConnection])
    end
  end
  
  it "should require Basic Authentication" do
    get '/'
    #last_response.should eql(true)
    last_response.status.should eql(401)
    last_response.headers["WWW-Authenticate"].should eql("Basic realm=\"Restricted Area\"")
    #last_response["Location"].should eql("http://example.org/ftprs/users/new")
    #last_response.body.should == 'Hello World'
  end
  
  it "should redirect / to ftpusers/new" do
    authorize "admin", "admin"
    get '/'
    #last_response.should eql(true)
    last_response.status.should eql(302)
    #last_response.headers["WWW-Authenticate"].should eql("Basic realm=\"Restricted Area\"")
    last_response["Location"].should eql("http://example.org/ftprs/users/new")
    #last_response.body.should == 'Hello World'
  end
  
  it "should have a /ftprs/users/list page" do
    authorize "admin", "admin"
    get "/ftprs/users/list"
    last_response.status.should eql(200)
  end
  
  it "should have a /ftprs/users/new page" do
    authorize "admin", "admin"
    get "/ftprs/users/new"
    last_response.status.should eql(200)
  end
  
  it "should have a /ftprs/users/edit page" do
    authorize "admin", "admin"
    get "/ftprs/users/edit"
    last_response.status.should eql(200)
  end
  
  it "should allow to post to /ftprs/users/edit/:uid page" do
    #@ldap_mock.should_recieve(:search)
    params = {
      "cn" => "testuser"
    }
    testuser = {
      "cn" => ["testuser"]
    }
    uid = "100"
    @ldap_mock = mock(FTPrs::Server::LDAPConnection)
    FTPrs::Server.ldap = @ldap_mock
    @ldap_mock.should_receive(:search).with("ou=People,dc=ftp,dc=zinio,dc=com", uid).and_return([testuser])
    @ldap_mock.should_receive(:modify).with({:name=>"admin", :ip=>"127.0.0.1"}, "cn=testuser,ou=People,dc=ftp,dc=zinio,dc=com", [])
    Net::LDAP::Filter.should_receive(:eq).with("uidNumber", uid).and_return(uid)
    authorize "admin", "admin"
    post "/ftprs/users/edit/#{uid}", params 
    #last_response.should eql(true)
    last_response.status.should eql(200)
  end
  
  it "should cache user list" do
    
  end
  
  it "should cache individual users" do
    
  end
  
  it "should cache user edits" do
  
  end
  
  it "should cache new users" do
  
  end
end