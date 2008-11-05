module Deployable
  class Runner < Deployable::Base
    ## These are are all autoloaded by the YAML config file
    attr_accessor :admins, :workers,:class,:controller,:config,:responders,:disco_features
    
    def run
      EM.run do
        @responders = Array.new
        clientSetup
        loadWorkers
        configResponder
        @logger.debug("Spawn new MUC client")
      end
    end

    def configResponder
      base_responder = Discovery::Responder.new(@client)
      @logger.debug("Features: #{@disco_features}")
      @disco_features.each do |feature|
        feature.each do |key,value|
          base_responder.add_feature("#{key}:#{value}")
        end
      end
      @workers.each do |command,worker_spec|
        ## Add an item for each command
        item = Discovery::Item.new(@botname, "#{command}", "#{command}")
        base_responder.items << item
        responder = Discovery::Responder.new(@client, "#{command}")
        ## Sites will be added as nodes to the command item (added above as an item to the top level)
        @workers["#{command}".to_sym][:sites].each do |site|
          responder.add_feature("#{command}:#{site[:name]}")
        end
        @responders << responder
      end
      @responders << base_responder
    end
    
    def loadWorkers
      @workers.each do |command,worker_spec|
        @logger.debug "#{worker_spec[:worker]} : #{worker_spec[:worker].class}"
        self.send(:require, "deployable/#{worker_spec[:worker]}")
      end
    end
    
    def listWorkers
      message = ''
      @workers.each do |command,worker_spec|
        message = message + "#{command}: #{worker_spec[:desc]}\r\n"
      end
      message
    end
    
    def clientSetup
      super
      @client.add_message_callback { |msg|
        if @admins.include?(msg.from.resource)
          if msg.body == 'list'
            send_msg(msg.from.resource.to_s,listWorkers)
          elsif msg.body == 'reload'
            @workers.each do |command,worker_spec|
              $".delete("deployable/#{worker_spec[:worker]}.rb")
              self.send(:require, "deployable/#{worker_spec[:worker]}")
            end
          else
            begin
              stanza = msg.body
              atoms = stanza.split("\n")
              ## Not sure I like this anymore. I am thinking just the command and no
              ## or minimal config sent to the worker.
              ## Makes the worker more specific, or have a config for the worker.
              
              command = atoms.shift
              @logger.debug("calling #{command} : #{atoms.to_s}")
              worker = eval("#{@workers[command.to_sym][:worker].capitalize}.new")
              worker.callback {|code| send_msg(msg.from.resource.to_s,"#{code[:message]}")}
              worker.errback {|code| send_msg(msg.from.resource.to_s,"Failure #{code[:message]}")}
              worker.send(command, atoms.join("\n"))
            rescue
              @logger.debug "Error calling #{command} #{$!}"
            end
          end
        else
          @logger.debug "I don't take orders from you #{msg.from.resource}"
        end
      }
    end
  end
end
