require 'pp'
require 'stringio'
require 'net/ssh'
require 'deployable/deploymachine'

module Deployable
  class Controller < Deployable::Base
    include Jabber
    include Log4r

    attr_accessor :registry, :client, :rules, :lbhost, :lbuser, :rescode, :commandids
    
    def initialize(args = Hash.new)
      super(args)
      @registry = Hash.new
      @rules = Hash.new
      @commandids = Array.new
    end
        
    def run
      EM.run do
        clientSetup
        processRoster
      end
    end

    ## Do service discovery on *jid
    ## Returns an array of features provided by the jid
    def query(jid)
      features = []
      iq = iq_get(:recip => jid, :service => 'disco', :query => 'items')
      @client.send_with_id(iq) {|reply|
        reply.query.items.each do |item|
          iq = iq_get(:recip => jid, :service => 'disco', :query => 'info')
          iq.query.add_attribute('node',"#{item.node}")
          @client.send_with_id(iq) {|reply|
            reply.query.features.each do |feature|
              features << feature
            end
          }
        end
      } 
      features     
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
                add_to_registry(JID.new(element.attributes['jid']))
              end
            end
          }
        else
          @logger.debug("#{jid} is not online")
        end
      end
    end
    
    def add_to_registry(jid = nil)
      if jid
        features = query(jid)
        @registry[jid.bare.to_s] = RosterMember.new(:jid => jid, :features => features)        
      end
    end
    
    def clientSetup
      super
      @client.add_message_callback(100) {|message|
        agent = message.from
        if message.body =~ /registry/
          tmpl = "%s\n\tNode: %s\n\tJID: %s\n\tFeatures: %s\n"
          str = "\n"
          @registry.each do |host,member|
            str = str + sprintf(tmpl, host, member.jid.node, member.jid, member.features.join(','))
          end
          send_msg(agent.to_s, str, message.type)
        elsif message.body =~ /reload runner/
          processRoster
          send_msg(agent.to_s, 'Reloaded', message.type)
        else
          atoms = message.body.split("\n")
          command = atoms.shift
          ## Scan @registry to see if a host has registered the command?
          @registry.each do |host,member|
            if member.features.include?(command)
              @logger.debug("Found client for #{command}")
              deploy(command, atoms)
              break
            end
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
              add_to_registry(agent)
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
      @registry.each do |host,member|
        if member.features.include?(command)
          hosts << host
        end
      end
      ## Partition the hosts into 2 sets
      hostsets = hosts.partition {|host| hosts.index(host) % 2 == 0}
      hostsets.each do |hostset|
        next unless hostset.size > 0
        
        results = Hash.new
        ## New thought. Loop hosts to generate messages then
        ## Reloop to create a thread array and join each
        messageset = Hash.new
        hostthreads = Array.new
        
        hostset.each do |host|
          jid = JID.new(host)
          ## Remove the host from the laodbalancer
          host_lb(jid.node, :down)
          ## Send command to the runner object
          cmd = command.match(/^(.*?):/)[1]
          atoms.unshift(cmd)
          message = Message.new(host, atoms.join("\n"))
          @logger.debug(message.to_s)
          message.id = Jabber::IdGenerator.generate_id
          messageset[host] = message
        end
        
        
        ## This spins off in a different thread, how can I deal?
        ## I need to wait until I get a response before moving on
        messageset.each do |host,message|
          @logger.debug("New thread for #{host}")
          hostthreads << Thread.new do
            machine = DeployMachine.new(:message => message, :stream => @client)
            machine.run
            until machine.done?
              sleep(0.1)
            end
            
            if machine.response?
              results[machine.jid] = true
              @logger.info("#{host}: #{machine.message}")
            else
              results[machine.jid] = false
              @logger.error("#{host}: #{machine.message}")
            end
          end
        end
        hostthreads.each {|thr| thr.join}

        ## Run post deployment tests
        ## If more hosts failed then succedded, fail the entire deployment
        host_results = results.partition {|res| res}
        @logger.debug("Results: #{pp results}")
        if host_results[0].size <= host_results[1].size
          @logger.error("More hosts failed then succedded in this deployment, canceling the rest")
          return
          ## SuperFail
        end
        ## Bring each successful deploy back online
        results.each do |screen,result|
          @logger.debug("#{screen} #{result}")
          if result
            host_lb(screen, :up)
          else
            @logger.debug("#{screen} failed")
          end
        end
      end
      ## Generate some sort of result message, logging, etc
    end
    private :deploy

    def host_lb(host, action = nil)
      return true

=begin      
      if [:up,:down].include?(action)
        begin
          Net::SSH.start(@lbhost,@lbuser) do |ssh|
            @logger.debug("b node #{host} #{action.to_s}")
            output = ssh.exec!("b node #{host} #{action.to_s}")
            @logger.debug("SSH: #{output}")
          end
        rescue
          @logger.err("Unable to contact #{lbhost}")
        end
      end
=end
    end
    private :host_lb

    def send_command(host,command,atoms)
      ## Send the deploy command to the specified host
      ## YAML command structure is initially on the table
      command = command.match(/^(.*?):/)[1]
      atoms.unshift(command)
      message = Message.new(host, atoms.join("\n"))
      status = false
      @client.send_with_id(message) {|reply|
        response,message = reply.match(/^(.*?)\s(.*)/)[1,2]
        if response == 'OK'
          status = true
          @logger.info("#{host}: #{message}")
        else
          @logger.err("#{host}: #{message}")
        end
      }
      status
    end
    private :send_command
  end
end