#!/usr/bin/env ruby

$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'pp'
require 'ftprs'
require 'yaml'
require 'json'
require 'daemons'

@config = JSON.parse(open(ARGV[0]).read, :symbolize_names => true)

FTPrs::Server.load(@config)

if (ENV['RACK_ENV'] == "production")
  Daemons.daemonize(
    :log_output => true,
    :app_name => "ftprs",
    :backtrace  => true,
    :dir_mode => :normal,
    :dir => @config[:env][:log],
    :log_dir => @config[:env][:log]
  )
end

FTPrs::Server.start