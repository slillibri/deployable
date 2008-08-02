require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'yaml'

include Jabber
include Log4r

module Deployable
  class Base
    attr_accessor :channel, :botname, :password, :logger, :debug, :host, :muc
    
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
      @logger.outputters = Log4r::FileOutputter.new("#{loggertype}", :filename => "#{conf[:logfile]}", :trunc => false)
      @logger.level = conf[:loglevel] || DEBUG
      if (@debug == true)
        Jabber.debug = true
      end
      @logger.debug("Initialization complete")      
    end
    
    ##Send an XMPP message
    def send_msg to, text
      message = Message.new(nil, text)
      message.type = :normal
      @logger.debug YAML.dump(message)
      @muc.send(message,to)
    end 
    def clientSetup
      client = Client.new(JID.new(@botname))
      client.connect(@host)
      client.auth(@password)
      pres = Presence.new
      pres.priority = 5
      client.send(pres)
      
      client.on_exception do |ex, stream, symb|
        @logger.debug("Disconnected, #{ex}, #{symb}")
        @logger.error("FAIL")
        exit
      end
      client
    end
  end
end