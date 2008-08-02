require 'xmpp4r'
require 'xmpp4r/muc'
require 'eventmachine'
require 'log4r'
require 'deployable/worker'
require 'yaml'

include Jabber
include Log4r
module Deployable
  class Runner < Deployable::Base
    ## These are are all autoloaded by the YAML config file
    attr_accessor :admins, :workers
        
    def run
      EM.run do
        client = clientSetup
        loadWorkers
        @muc = self.mucSetup(client)
        @logger.debug("Spawn new MUC client")
      end
    end

    def loadWorkers
      @workers.each do |command,worker_spec|
        self.send(:require, "deployable/#{worker_spec[:worker]}")
        w = eval("#{worker_spec[:worker].capitalize}.new")
        @workers["#{command}"] = {:worker => w, :desc => worker_spec[:desc]}
      end
    end
    
    def listWorkers
      message = ''
      @workers.each do |command,worker_spec|
        message = message + "#{command}: #{worker_spec[:desc]}\r\n"
      end
      message
    end
    
    def mucSetup client
      muc = MUC::MUCClient.new(client)
      
      muc.add_message_callback { |msg|
        if @admins.include?(msg.from.resource)
          if msg.body == 'list'
            send_msg(msg.from.resource.to_s,listWorkers)
          end
          begin
            stanza = msg.body
            atoms = stanza.split(' ')
            command = atoms.shift
            @logger.debug("calling #{command} : #{atoms.to_s}")
            worker = @workers["#{command}"][:worker]
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