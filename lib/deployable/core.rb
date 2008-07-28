require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'deployable/worker'
require 'yaml'
require 'pp'

include Jabber
include Log4r
module Deployable
  class Core
    attr_accessor :botname, :password, :channel, :logfile, :loglevel, :logger, :admins, :debug, :muc, :host

    def initialize(args = Hash.new)
      begin
        conf = YAML.load(File.open(args[:config]))
        conf.each {|key,value|
          self.send("#{key}=", value)
        }
        @logger = Log4r::Logger.new "deploy"
        @logger.outputters = Log4r::FileOutputter.new("deploy", :filename => self.logfile, :trunc => false)
        @logger.trace = true
        @logger.level = self.loglevel
        if(@debug == true) 
          Jabber.debug = true
        end
      rescue Exception => e
        puts "There was an exception #{e}"
        nil
      end
    end
    
    def run
      EM.run do
        @muc = self.mucSetup
        @logger.debug("Spawn new MUC client")
      end
    end

    def send_msg to, text
      message = Message.new(nil, text)
      message.type = :normal
      @muc.send(message,to)
    end
  
    def mucSetup
      begin
      client = Client.new(JID.new(@botname))
      client.connect(@host)
      client.auth(@password)
      pres = Presence.new
      pres.priority = 5
      client.send(pres)
      
      client.on_exception do |ex, stream, symb|
        @logger.debug("Disconnected, #{ex}, #{symb}")
        while (! stream.is_connected?)
          @logger.debug("Reconnecting")
          stream.connect
          stream.auth(@password)
        end
        end
      rescue
        @logger.debug("Retrying in 10 seconds")
        sleep(10)
        retry
      end
      muc = MUC::MUCClient.new(client)
      muc.add_message_callback { |msg|
        if @admins.include?(msg.from.resource)
          begin
            stanza = msg.body
            atoms = stanza.split(' ')
            command = atoms.shift
            @logger.debug("calling #{command} : #{atoms.to_s}")
            worker = Worker.new
            worker.callback {|code| send_msg(msg.from.resource.to_s,"#{code[:message]}")}
            worker.errback {|code| send_msg(msg.from.resource.to_s,"#{code[:message]}")}
            worker.send(command, atoms)
          rescue
            @logger.debug "Error calling #{command} #{$!}"
          end
        else
          @logger.debug "I don't take orders from you #{msg.from.resource}"
        end
      }
      muc.join("#{@channel}/#{client.jid.resource}")
    end
  end
end