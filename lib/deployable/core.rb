require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'deployable/worker'
require 'yaml'

include Jabber
include Log4r
module Deployable
  class Core
    attr_accessor :botname, :password, :channel, :logfile, :loglevel, :hbconf, :logger, :admins

    def initialize(args = Hash.new)
      begin
        conf = YAML.load(File.open(args[:config]))
        conf.each {|key,value|
          self.send("#{key}=", value)
        }
        @logger = Log4r::Logger.new "deploy"
        @logger.outputters = Log4r::FileOutputter.new("deploy", :filename => self.logfile, :trunc => false)
        @logger.level = self.loglevel
      rescue Exception => e
        puts "There was an exception #{e}"
        nil
      end
    end
    
    def run
      EM.run do
        muc = self.mucSetup
        @logger.debug("Spawn new MUC client")
        EM::PeriodicTimer.new(5) do
          muc.say('Still alive')
        end
      end
    end
  
    def mucSetup
      client = Client.new(JID.new(@botname))
      client.connect
      client.auth(@password)
      pres = Presence.new
      pres.priority = 5
      client.send(pres)
      
      muc = MUC::SimpleMUCClient.new(client)
      muc.on_message {|time,nick,text|
        @logger.debug "Received message #{text} from #{nick}"
        # Only admins can talk to me to prevent looping
        if admins.include?(nick)          
          args = text.split(' ')
          command = args.shift
          @logger.debug "#{command} : #{args}"
          worker = Deployable::Worker.new
          worker.callback {|code| muc.say("#{code[:code]} #{code[:message]}")}
          worker.errback {|code| muc.say("#{code[:code]} #{code[:message]}")}
          worker.send(command,args)
        end
      }

      muc.on_private_message {|time,nick,text|
        # Only admins can talk to me to prevent looping
        if admins.include?(nick)
          @logger.debug "Received private message #{text} from #{nick}"
          args = text.split(' ')
          command = args.shift
          @logger.debug "#{command} : #{args}"
          worker = Deployable::Worker.new
          worker.callback {|code| muc.say("#{code[:code]} #{code[:message]}")}
          worker.errback {|code| muc.say("#{code[:code]} #{code[:message]}")}
          worker.send(command,args)
        end
      }

      muc.join("#{@channel}/#{client.jid.resource}")
    end
  end
end