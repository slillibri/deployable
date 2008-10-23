require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'yaml'
require 'pp'

require 'stringio'

module Deployable
class Controller < Deployable::Base
    include Jabber
    include Log4r

    attr_accessor :registry, :client, :rules, :rulesdir
    
    def initialize(args = Hash.new)
      super(args)
      @registry = Hash.new
    end
    
    def run
      EM.run do
        clientSetup
        @muc = mucSetup
        EM::PeriodicTimer.new(10) do
          get_room_participants
        end
      end
    end

    def loadRules
      
    end

    def clientSetup
      super
      @client.add_message_callback(100) {|message|
        agent = message.from
        if message.body =~ /registry/          
          str = StringIO.new
          PP.pp(@registry, str)
          str.rewind
          send_msg(agent.resource.to_s, str.read)
        end        
      }
      @client.add_message_callback(100) {|message|
        agent = message.from
        if message.body =~ /reload runner/
          get_room_participants
          send_msg(agent.resource.to_s, 'Reloaded')          
        end
      }
    end

    def iq_get args = Hash.new
      iq = Iq.new_query(:get, args[:recip])
      query = REXML::Element.new('query')
      query.add_namespace("http://jabber.org/protocol/#{args[:service]}\##{args[:query]}")
      iq.query = query
      iq
    end

    def get_room_participants
      @logger.debug("Finding participants")
      iq = iq_get(:recip => @channel, :service => 'muc', :query => 'admin')
      iq.query.add_element('item', {'role'=>'participant'})
      @logger.debug("PARTICIPANTS: #{iq}")
      @client.send_with_id(iq) {|reply|
        @logger.debug("RESULT: #{reply.query.class}")
          reply.query.items.each do |item|
            unless @registry.has_key?(item.jid.bare.to_s)
              jid = item.jid
              @registry[jid.bare.to_s] = []
              @logger.debug("Registering #{jid}")
              iq = iq_get(:recip => jid, :service => 'disco', :query => 'items')
              @logger.debug("ITEM-DISCO: #{iq}")
              @client.send_with_id(iq) {|reply2|
                @logger.debug("REPLY2: #{reply2}")
                reply2.query.items.each do |item|
                  iq = iq_get(:recip => jid, :service => 'disco', :query => 'info')
                  iq.query.add_attribute('node',"#{item.node}")
                  @client.send_with_id(iq) {|reply3|
                    reply3.query.features.each do |feature|
                      @registry[jid.bare.to_s] << feature
                      @logger.debug("#{feature}")
                    end
                  }
                end
              }
            end                
          end
      }
    end

    def mucSetup
      muc = MUC::MUCClient.new(@client)
      ##need to do the presence callback at somepoint to kill the polling for new clients
      muc.add_message_callback(100) { |message|
        @logger.debug("#{message}")
        agent = message.from
        ## Validate sender
        ## Parse message (systems, action, args, etc)
        ## (message will be a YAML structure)
        ## Start the process        
      }
      muc.add_message_callback(100) { |message| 
        agent = message.from
        if message.body =~ /registry/          
          str = StringIO.new
          PP.pp(@registry, str)
          str.rewind
          send_msg(agent.resource.to_s, str.read)
        end
      }
      muc.join("#{@channel}/#{client.jid.resource}")            
      muc
    end
  end
end