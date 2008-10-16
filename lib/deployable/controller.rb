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

    attr_accessor :registry, :client
    
    def initialize(args = Hash.new)
      super(args)
      @registry = Hash.new
    end
    
    def run
      EM.run do
        clientSetup
        @muc = mucSetup
        EM::PeriodicTimer.new(10) do |poll|
          get_room_participants
        end
      end
    end

    def add_feature key, feature
      if @registry.has_key?(key)
        @logger.debug "Adding #{feature}"
        unless @registry[key].include?(feature)
          @registry[key] << feature
        end
      end
      @logger.debug @registry 
    end

    def disco presence, type, attributes = nil
      @logger.debug "Disco'ing #{presence.from.to_s}"
      iq = Iq.new_query(:get, "#{presence.from.to_s}")
      query = REXML::Element.new('query')
      query.add_namespace("http://jabber.org/protocol/disco\##{type}")
      if attributes
        attributes.each do |key, value|
          query.add_attribute(key, value)
        end
      end
      iq.query = query
      @logger.debug(iq)
      iq
    end

    ##Holy sweet monkey refactor me
    ##I suck
    def get_room_participants
      @logger.debug("Finding participants")
      iq = Iq.new_query(:get, "#{@channel}")
      query = REXML::Element.new('query')
      query.add_namespace('http://jabber.org/protocol/muc#admin')
      query.add_element('item', {'role'=>'participant'})
      iq.query = query
      @logger.debug("PARTICIPANTS: #{iq}")
      @client.send_with_id(iq) {|reply|
        @logger.debug("RESULT: #{reply.query.class}")
          reply.query.items.each do |item|
            unless @registry.has_key?(item.jid.bare.to_s)
              jid = item.jid
              @registry[jid.bare.to_s] = []
              @logger.debug("Registering #{jid}")
              iq = Iq.new_query(:get, "#{jid}")
              query = REXML::Element.new('query')
              query.add_namespace("http://jabber.org/protocol/disco\#items")     
              iq.query = query         
              @logger.debug("ITEM-DISCO: #{iq}")
              @client.send_with_id(iq) {|reply2|
                @logger.debug("REPLY2: #{reply2}")
                reply2.query.items.each do |item|
                  iq = Iq.new_query(:get, "#{jid}")
                  query = REXML::Element.new('query')
                  query.add_namespace('http://jabber.org/protocol/disco#info')
                  query.add_attribute('node',"#{item.node}")
                  iq.query = query
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


    def register_runner presence
      ## Initiate service disco on new runner
      ## Poll Items for node based information
      ## For each node, poll for Item and Info
      ## Poll Info

      ## Discover workers
      iq = disco(presence, "items")
      @client.send(iq) do |reply|
        @logger.debug("Sent #{iq}")
        get_elements(reply, presence)
      end
    end

    def get_elements reply, presence
      reply.each_element do |element|
        @logger.debug("#{reply}\n#{presence}")
        element.items.each do |item|
          @logger.debug("getting info on item #{item}")
          get_features(item, presence)
        end
      end
    end
    
    def get_features item, presence
      iq = disco(presence, "info", {'node' => item.iname})
      @client.send(iq) do |reply|
        reply.each_element do |element|
          if element.respond_to?(:features)
            element.features.each do |feature|
              add_feature(reply.from.to_s, feature)
            end
          end
        end
      end
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