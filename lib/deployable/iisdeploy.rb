require 'eventmachine'
require 'log4r'

module Deployable
  class IISDeploy
    def initialize(*args)
      @logger = Log4r::Logger.new "workerlog"
      @logger.outputter = Log4r::FileOutputter.new("workerlog", :filename => "worker.log", :trunc => false)
      @logger.level = DEBUG
    end
    
    def deploy *args
      conf = args[0]
      begin
        # Copy files located at conf[:source] to tmp
        # Unpack?
        # Remove conf[:self] from conf[:pool]
        # Copy files from conf[:source] to conf[:dst]
        # Perform each conf[:system] action in order
        # Add conf[:self] to conf[:pool]
        set_deferred_status :succeeded {:message => "#{conf[:web]} deployed"}
      rescue
        set_deferred_status :failed {:message => "#{conf[:web]} failed to deploy"}
      end
    end
  end
end