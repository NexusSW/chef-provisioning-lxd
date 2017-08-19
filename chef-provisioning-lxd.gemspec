# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
$LOAD_PATH.push File.expand_path('../lib/surro-gate/lib', __FILE__)
require 'chef/provisioning/lxd_driver/version'

Gem::Specification.new do |spec|
  spec.name          = 'chef-provisioning-lxd'
  spec.version       = Chef::Provisioning::LXDDriver::VERSION
  spec.authors       = ['Sean Zachariasen']
  spec.email         = ['thewyzard@hotmail.com']

  spec.summary       = 'LXD Driver for Chef Provisioning'
  # spec.description   = %q{TODO: Write a longer description or delete this line.}
  # spec.homepage      = 'http://git.thewyzard.net'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.

  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.files += `cd lib/surro-gate; git ls-files -z`.split("\x0").map { |f| 'lib/surro-gate/' + f }.reject do |f|
    f.match(%r{/(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'chef-provisioning'
  spec.add_dependency 'hyperkit', '~> 1.1.0'
  # spec.add_dependency  'surro-gate', '~> 0.2.2' # , github: 'skateman/surro-gate'

  # Surro-gate dependency
  # remove this line when I switch away from the submodule
  spec.add_dependency 'nio4r', '~> 2.0'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
