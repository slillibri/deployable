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
        processRoster
      end
    end

    def query(jid)
      @registry[jid.bare.to_s] = []
      iq = iq_get(:recip => jid, :service => 'disco', :query => 'items')
      @client.send_with_id(iq) {|reply|
        reply.query.items.each do |item|
          iq = iq_get(:recip => jid, :service => 'disco', :query => 'info')
          iq.query.add_attribute('node',"#{item.node}")
          @client.send_with_id(iq) {|reply|
            reply.query.features.each do |feature|
              @registry[jid.bare.to_s] << feature
            end
          }
        end
      }      
    end

    def processRoster
      @roster.items.each do |jid,rosteritem|
        ## This contains the resourceless jid in the roster
        ## We need to query item first then get the jid from the
        ## username item
        @logger.debug("Processing #{jid}")
        if rosteritem.online?
          @logger.debug("#{jid} is Online")
          ## This is hacky and there has to be a better way to do it
          iq = iq_get(:recip => jid, :service => 'disco', :query => 'items')
          @client.send_with_id(iq) {|reply|
            reply.query.elements.each do |element|
              if element.attributes['name'] == jid.node
                query(JID.new(element.attributes['jid']))
              end
            end
          }
        else
          @logger.debug("#{jid} is not online")
        end
      end
    end

    def clientSetup
      super
      @client.add_message_callback(100) {|message|
        agent = message.from
        @logger.debug(agent.to_s)
        @logger.debug(" Client processing message callback")
        if message.body =~ /registry/
          str = StringIO.new
          PP.pp(@registry, str)
          str.rewind
          send_msg(agent.to_s, str.read, message.type)
        end        
      }
      @client.add_message_callback(100) {|message|
        agent = message.from
        if message.body =~ /reload runner/
          processRoster
          send_msg(agent.to_s, 'Reloaded', :chat)
        end
      }
      @client.add_presence_callback(100) {|presence|
        ## Process online and offline presence announcements
        agent = presence.from
        if presence.type == 'online'
          query(agent)
        elsif presence.type == 'offline'
          @registry.delete(agent)
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
      muc.add_message_callback(99) { |message| 
        agent = message.from
        @logger.debug("Muc processing message callback")
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