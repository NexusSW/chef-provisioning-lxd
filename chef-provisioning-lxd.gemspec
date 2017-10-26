# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'chef/provisioning/lxd_driver/version'

Gem::Specification.new do |spec|
  spec.name          = 'chef-provisioning-lxd'
  spec.version       = Chef::Provisioning::LXDDriver::VERSION
  spec.authors       = ['Sean Zachariasen']
  spec.email         = ['thewyzard@hotmail.com']

  spec.summary       = 'LXD Driver for Chef Provisioning'
  spec.homepage      = 'https://github.com/NexusSW/chef-provisioning-lxd'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'chef-provisioning'
  spec.add_dependency 'lxd-common', '~> 0.1'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'simplecov'
end
