require 'eventmachine'
require 'yaml'
require 'ftools'
require 'fileutils'
require 'zip/zip'

module Deployable
  class MissingSourceException < StandardError
  end
  
  class Iisdeploy
    include EM::Deferrable
    
    def deploy args
      conf = YAML.load("#{args}")
      systemErrors = Array.new()
      
      begin
        # Check that we have the source
        unless File.exists?(conf[:source])
          raise MissingSourceException.new('source directory missing')
        end
        unless File.exists?(conf[:tmp])
          Dir.mkdir(conf[:tmp])
        end

        # Unpack?
        if File.extname(conf[:source]) == ".zip"
          unzip_file(conf[:source], conf[:tmp])
          #File.delete("#{conf[:source]}")
        end
                
        # Rename conf[:dest] to conf[:dest_bak] (Remove existing backup)
        if File.exists?("#{conf[:dest]}_bak")
          FileUtils.rm_rf("#{conf[:dest]}_bak")
        end
        
        File.move(conf[:dest], "#{conf[:dest]}_bak")
        
        # Copy files from conf[:source] to conf[:dst]
        Dir.mkdir(conf[:dest])
        FileUtils.cp_r("#{conf[:tmp]}/.", conf[:dest])
        
        # Cleanup conf[:tmp] directory
        FileUtils.rm_r("#{conf[:tmp]}/")
        
        # Perform each conf[:system] action in order
        if conf[:system] && conf[:system].respond_to?(:each)
          conf[:system].each do |action|
            begin
              unless system(action)
                raise StandardError.new("#{action} failed")
              end
            rescue Exception => e
              systemErrors.push(e)
            end            
          end
        end
        
        if systemErrors.size > 0
          errorString = "SystemErrors:\n"
          systemErrors.each do |error|
            errorString << "#{error}\n"
          end
          set_deferred_status :failed, {:message => errorString}
          return
        end
        set_deferred_status :succeeded, {:message => "#{conf[:web]} deployed"}
      rescue MissingSourceException => e
        set_deferred_status :failed, {:message => "Missing source #{conf[:source]}"}
      rescue Exception => e
        set_deferred_status :failed, {:message => "#{conf[:web]} failed to deploy Exception => #{e} : #{$@[0]}"}
      end
    end
    
    def unzip_file(source,tmp)
      begin
        Zip::ZipFile.open(source) do |zf|
          zf.each do |e|
            fpath = File.join(tmp,e.name)
            FileUtils.mkdir_p(File.dirname(fpath))
            zf.extract(e, fpath)
          end
        end
      rescue Exception => e
        raise e
      end      
    end
  end
end