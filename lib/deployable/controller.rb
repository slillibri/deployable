require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'yaml'

module Deployable
  class Controller < Deployable::Base
    include Jabber
    include Log4r

    attr_accessor :registry
    
    def initialize(args = Hash.new)
      super(args)
      @registry = Hash.new
    end
    
    def run
      EM.run do
        client = clientSetup
        @muc = mucSetup(client)
      end
    end

    def register_runner presence
      ## Initiate service disco on new runner
      
    end
    
    def process_registration agent, message
      config_string = /^identity\n(.*)/m.match(message)
      config = YAML.load(config_string[1])
      if  config[:controller] == 'iis'
        
      end
    end
    def mucSetup client
      muc = MUC::MUCClient.new(client)
      ## Add new clients to the registry if they are unrecognized
      muc.add_join_callback(100) {|presence|
        unless  @registry.has_key?(presence.from)
          register_runner(presence)
        end
      }
      muc.add_message_callback(100) { |message|
        agent = message.from
        ## Validate sender
        ## Parse message (systems, action, args, etc)
        ## (message will be a YAML structure)
        ## Start the process        
      }
      muc.add_message_callback(99) { |message| 
        agent = message.from
        if message.body =~ /^identity/          
          process_registration(agent, message.body)
        end
      }
      muc.join("#{@channel}/#{client.jid.resource}")            
      muc
    end
  end
end