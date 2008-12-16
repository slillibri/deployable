require 'xmpp4r'
require 'xmpp4r/muc'
require 'xmpp4r/discovery'
require 'xmpp4r/roster'
require 'eventmachine'
require 'log4r'
require 'yaml'


module Deployable
  ## This is the base class for Deployable objects. It does basic initialization 
  ## and setup of the XMPP client
  class Base
    include Jabber
    include Log4r

    attr_accessor :channel, :botname, :password, :logger, :debug, :host, :muc, :roster, :client
    
    def initialize args = Hash.new
      conf = YAML.load(File.open(args[:config]))
      ##Assign all the values we respond to from the config
      conf.each do |attr,value|
        if self.respond_to?("#{attr}=")
          self.send("#{attr}=", value)
        end        
      end
      
      ##Setup the logger
      loggertype = self.class.to_s.downcase
      @logger = Log4r::Logger.new("#{loggertype}")
      @logger.trace = true
      o = Log4r::FileOutputter.new("#{loggertype}", :filename => "#{conf[:logfile]}", :trunc => false)
      o.formatter = Log4r::BasicFormatter
      @logger.outputters = o
      @logger.level = conf[:loglevel] || DEBUG
      if (@debug == true)
        Jabber.debug = true
        self.send(:require, 'pp')
      end
      @logger.debug("Initialization complete")      
    end
    
    ##Send an XMPP message
    def send_msg to, text, type = :normal, id = nil
      message = Message.new(to, text).set_type(type)
      message.id = id if id
      @logger.debug(message.to_s)
      @client.send(message)
    end 
    
    ##Setup the basic xmpp client
    ##
    def clientSetup
      @client = Client.new(JID.new(@botname))
      @client.connect(@host)
      @client.auth(@password)
      @roster = Roster::Helper.new(@client)
      pres = Presence.new
      pres.priority = 5
      pres.set_type(:available)
      pres.set_status('online')
      @client.send(pres)
      @roster.wait_for_roster
      
      @client.on_exception do |ex, stream, symb|
        @logger.debug("Disconnected, #{ex}, #{symb}")
        exit
      end
    end
  end
end