# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "chef/provisioning/lxd_driver/version"

Gem::Specification.new do |spec|
  spec.name          = "chef-provisioning-lxd"
  spec.version       = Chef::Provisioning::LXDDriver::VERSION
  spec.authors       = ["Sean Zachariasen"]
  spec.email         = ["thewyzard@hotmail.com"]
  spec.license       = "Apache-2.0"

  spec.summary       = "Chef Provisioning Driver for LXD"
  # spec.description   = %q{TODO: Write a longer description or delete this line.}
  # spec.homepage      = "http://git.thewyzard.net"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.

  # if spec.respond_to?(:metadata)
  #   spec.metadata["allowed_push_host"] = "TODO: Set to "http://mygemserver.com""
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "chef-provisioning"
  spec.add_dependency "lxd-common"
  spec.add_dependency "nio4r-websocket", "~> 0.7"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
