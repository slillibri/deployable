require 'pp'
require 'stringio'

module Deployable
  class Controller < Deployable::Base
    include Jabber
    include Log4r

    attr_accessor :registry, :client, :rules, :loadpath
    
    def initialize(args = Hash.new)
      super(args)
      @registry = Hash.new
      @rules = Hash.new
      unless @loadpath
        @loadpath = File.expand_path(File.join(File.dirname(__FILE__), "../rules"))
      end
    end
    
    def run
      EM.run do
        clientSetup
        processRoster
      end
    end

    ## Do service discovery on *jid
    def query(jid)
      @registry[jid.bare.to_s] = []
      iq = iq_get(:recip => jid, :service => 'disco', :query => 'items')
      @client.send_with_id(iq) {|reply|
        reply.query.items.each do |item|
          iq = iq_get(:recip => jid, :service => 'disco', :query => 'info')
          iq.query.add_attribute('node',"#{item.node}")
          @client.send_with_id(iq) {|reply|
            reply.query.features.each do |feature|
              ## This is where the rules template will be loaded
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
      @client.add_message_callback(100) {|message|
        agent = message.from
        atoms = message.body.split(" ")
        command = atoms.shift
        ## Scan @registry to see if a host has registered the command?
        @registry.each do |host,commands|
          if commands.include?(command)
            deploy(command, atoms)
            return
          end
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
    
    def deploy(command, atoms)
      hosts = []
      ## Determine which hosts respond to this command
      @registry.each do |host,commands|
        if commands.include?(command)
          hosts << host
        end
      end
      ## Partition the hosts into 2 sets
      hostsets = hosts.partition {|host| hosts.index(host) % 2 == 0}
      hostsets.each do |hostset|
        hostset.each do |host|
          results = {}
          ## Remove the host from the laodbalancer
          remove_from_lb(host)
          ## Send command to the runner object
          results[host] = send_command(host, command, atoms)
        end
        ## Run post deployment tests
        ## If more hosts failed then succedded, fail the entire deployment
        host_results = results.partition {|res| res}
        if host_results[0].size < host_results[1].size
          ## SuperFail
        end
        ## Bring each successful deploy back online
        results.each do |host,result|
          add_to_lb(host) if result
        end
      end
      ## Generate some sort of result message, logging, etc
    end
    private :deploy
    
    def remove_from_lb(host)
      ## Net::SSH to f5 to run 'b node nodename down'
    end
    private :remove_from_lb
    
    def add_to_lb(host)
      ## Opposite of above, should probably be a single command
    end
    private :add_to_lb
    
    def send_command(host,command,atoms)
      ## Send the deploy command to the specified host
      ## YAML command structure is initially on the table
      
    end
  end
end