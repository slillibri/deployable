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
        ## We need to query #items first then get the jid from the
        ## item where name == jid.node (the username part of the jid)
        ## I need the resource to di the service disco on the bot
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
        if @roster.find(agent)
          @logger.debug("#{presence.type.to_s}")
          unless agent == @botname
            if presence.type.nil?
              query(agent)
            elsif presence.type == :unavailable
              @registry.delete(agent.bare.to_s)
            end
          end
        end
      }
    end

    def iq_get(args = Hash.new)
      iq = Iq.new_query(:get, args[:recip])
      query = REXML::Element.new('query')
      query.add_namespace("http://jabber.org/protocol/#{args[:service]}\##{args[:query]}")
      iq.query = query
      iq
    end
  end
end