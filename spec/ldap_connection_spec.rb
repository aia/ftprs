$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'spec_helper'

describe "FTPrs::Server::LDAPConnection" do
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
      }
    }
    @test_ds = mock(Net::LDAP)
    Net::LDAP.stub(:new).and_return(@test_ds)
    @custom_output = mock(StringIO)
    @custom_output.stub(:write).and_return(true)
    @ldap = FTPrs::Server::LDAPConnection.new(@test_config)
  end
  
  it "should properly initialize" do
    @ldap.config.should eql(@test_config)
  end
  
  it "should log messages" do
    @ldap.instance_variable_set(:@lh, @custom_output)
    message = "Test message"
    @custom_output.should_receive(:puts).with(message)
    @ldap.log(message)
  end
  
  it "should hash a password" do
    password = "test_password"
    result = "{CRYPT}AAX12SuzhSffQ"
    @ldap.stub(:rand).and_return(0)
    @ldap.crypt(password).should eql(result)
  end
  
  it "should change a users's password and log" do
    password = "test_password"
    requestor = {
      :name => "admin",
      :ip => "127.0.0.1"
    }
    basedn = "ou=People,dc=ftp,dc=example,dc=com"
    result = {
      :status => 1,
      :message => "Success",
      :values => ""
    }
    @ldap.instance_variable_set(:@lh, @custom_output)
    @custom_output.should_receive(:puts).with([
      "#{requestor[:name]} #{requestor[:ip]}",
      "operation replace password \"#{password}\" for",
      "#{basedn}"
    ].join(" "))
    @ldap.set_password(requestor, basedn, password).should eql(result)
  end
  
  it "should search LDAP" do
    basedn = "ou=People,dc=ftp,dc=example,dc=com"
    entry = {
      :sn=>"User1",
      :givenname=>"FTP",
      :gecos=>"FTP User,1633 SA, , ,00000000,user2",
      :cn=>"1633",
      :mail=>"",
      :sambasid=>"S-1-0-0-22048",
      :homedirectory=>"/data/ftp/home/1633",
      :uid=>"1633",
      :loginshell=>"/etc/ftponly",
      :uidnumber=>"10524",
      :dn=>"cn=1633,ou=People,dc=ftp,dc=example,dc=com",
      :gidnumber=>"10524",
      :userpassword=>["{CRYPT}AAX12SuzhSffQ"]
    }
    ldap_result = mock(Object)
    ldap_result.should_receive(:code).and_return(0)
    test_ds = mock(Object)
    test_ds.should_receive(:search).and_yield(entry)
    test_ds.should_receive(:get_operation_result).and_return(ldap_result)
    @ldap.instance_variable_set(:@ds, test_ds)
    ret = {
      :status => 1,
      :message => "Success",
      :values => [entry]
    }
    @ldap.search(basedn).should eql(ret)
  end
  
  it "should find UID" do
    
  end
  
  it "should add an LDAP record" do
    
  end
  
  it "modify an LDAP record" do
    
  end
end