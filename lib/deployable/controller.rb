require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'yaml'

include Jabber
include Log4r

module Deployable
  class Controller < Deployable::Base
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
  
    def mucSetup client
      muc = MUC::MUCClient.new(client)
      muc.add_join_callback { |presence| 
        ##Got a presence object
        agent = presence.from
        to = JID.new("#{agent.node}@#{agent.domain}/#{agent.resource}")
        @logger.debug YAML.dump(to)
        @logger.debug "#{agent.to_s}"
        if !@registry.has_key?(agent.resource.to_s)
          @logger.debug "Sending list to #{agent.resource.to_s}"
          send_msg(to, "Hello")
        end
      }
      
      muc.join("#{@channel}/#{client.jid.resource}")            
    end
  end
end