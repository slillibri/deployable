require 'log4r'
require 'timeout'

module Deployable
  class DeployMachine
    include Log4r
    attr_accessor :message, :stream, :logger
    attr_reader :response, :jid, :code, :state
    
    STATES = [:error, :success]
    
    def initialize args = {}
      @message = args[:message]
      @stream = args[:stream]
      @state = :new
      
      @jid = @message.from
      @response = false
      
      @logger = Log4r::Logger.new("deploymachine")
      @logger.trace = true
      o = Log4r::FileOutputter.new("deploymachine", :filename => "deploymachine.log", :trunc => false)
      o.formatter = Log4r::BasicFormatter
      @logger.outputters = o
      @logger.level = DEBUG      
    end
    
    def run
      ## TODO, insert a timeout watcher here.
      @logger.debug("Running")
      @state = :running
      begin
        status = Timeout::timeout(15) {
          @stream.send(@message) {|reply|
            @logger.debug(reply.to_s)
            response,code = reply.body.match(/^(.*?)\n(.*)/)[1,2]
            @code = code
            if response == 'OK'
              @response = true
              @state = :success
            else
              @state = :error
            end
          }
        }
      rescue Timeout::Error
        @state = :error
      end
    end
    
    def done?
      @logger.debug(@state)
      STATES.include? @state
    end
    
    def response?
      @response
    end
  end
end