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

    def register_runner presence
      ## Initiate service disco on new runner
      ## Example stanza
      #<iq from='test@conference.haruhi.local/Scott Lillibridge' type='get' to='bot@haruhi.local/deploy' id='aac7a' xml:lang='en'>
      #<query xmlns='http://jabber.org/protocol/disco#info'/>
      #</iq>
      
      ## Poll Items for node based information
      ## For each node, poll for Item and Info
      ## Poll Info
      unless @registry.has_key?(presence.from.to_s)
        @registry[presence.from.to_s] = Array.new
      end

      ## Discover workers
      iq = disco(presence, "items")
      @client.send(iq) do |reply|
        if reply.type.to_s == 'result'
          reply.each_element do |element|
            if element.respond_to?(:items)
              element.items.each do |item|
                ## Refactor me later, please
                @logger.debug("Item: #{item.iname}")
                @logger.debug("disco'ing features")
                iq = disco(presence, "info", {'node' => item.iname})
                @logger.debug("IQ: #{pp iq}")
                @client.send(iq) do |reply|
                  if reply.type.to_s == 'result'
                    reply.each_element do |element|
                      if element.respond_to?(:features)
                        element.features.each do |feature|
                          @logger.debug "Feature: #{feature}"
                          add_feature(reply.from.to_s, feature)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end        
      end
    end

    def mucSetup
      muc = MUC::MUCClient.new(@client)
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