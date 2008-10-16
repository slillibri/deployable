require 'xmpp4r'
require 'xmpp4r/muc'
require 'xmpp4r/discovery'
require 'eventmachine'
require 'log4r'
require 'yaml'


module Deployable
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
      end
      @logger.debug("Initialization complete")      
    end
    
    ##Send an XMPP message
    def send_msg to, text
      message = Message.new(to, text)
      @muc.send(message,to)
    end 
    
    ##Setup the basic xmpp client
    def clientSetup
      @client = Client.new(JID.new(@botname))
      @client.connect(@host)
      @client.auth(@password)
      pres = Presence.new
      pres.priority = 5
      @client.send(pres)
      
      @client.on_exception do |ex, stream, symb|
        @logger.debug("Disconnected, #{ex}, #{symb}")
        exit
      end
    end
  end
end