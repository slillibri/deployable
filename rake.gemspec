require 'rubygems'
SPEC = Gem::Specification.new do |s|
  s.name         = "deployable"
  s.version      = "0.5.0"
  s.author       = "Scott Lillbridge"
  s.email        = "scott@thereisnoarizona.org"
  s.platform     = Gem::Platform::RUBY
  s.summary      = "An XMPP distributed worker library"
  s.files        = ["lib/deployable/base.rb",
  "lib/deployable/controller.rb",
  "lib/deployable/iisdeploy.rb",
  "lib/deployable/lifter.rb",
  "lib/deployable/runner.rb",
  "lib/deployable/worker.rb",
  "lib/deployable.rb"]
  
end
