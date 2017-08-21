# chef-provisioning-lxd

This is a Chef Provisioning Driver for allocating containers in LXD.  It can run directly on the host running the provisioning cookbook as well as remotely either by issuing `lxc` CLI commands via an SSH connection, or via LXD's REST API, if it is enabled.

_The development of this gem is in parallel with a cookbook (not yet published) that will assist with some of the complexities of mutliple machine/container/nested container deployments._ __Coming Soon__

## Installation

Add this line to your provisioning cookbook's Gemfile:

```ruby
gem 'chef-provisioning-lxd'
```

Or if you're provisioning locally, you can execute (*__coming soon__*):

    $ chef gem install chef-provisioning-lxd

## Quick Start

To create a container on your local machine:
```ruby
machine 'name' do
  driver 'lxd:localhost'
  machine_options alias: 'lts', server: 'https://cloud-images.ubuntu.com/releases', protocol: 'simplestreams'
  ...
end
```

The simplest remote invocation:
```ruby
machine 'name' do
  driver 'lxd:hostname'
  machine_options ...
  ...
end
```
The above will work if 'hostname' was provisioned by your cookbook, and lxd is now installed and configured.  This driver will 'make use' of the driver that provisioned 'hostname' to get access to its CLI.

Additionally, you can manually specify ssh details:
```ruby
with_driver 'lxd:hostname:8443', driver_options: { ssh_user: '...', ssh_options: { ... } }
```
in a form expected by [Chef::Provisioning::Transport::SSH](https://github.com/chef/chef-provisioning/blob/master/lib/chef/provisioning/transport/ssh.rb)'s constructor.

or if the REST API is enabled on 'hostname', then include the port number.  (*__Client Cert details TBD__*)
```ruby
machine 'name' do
  driver 'lxd:hostname:8443'
  machine_options ...
  ...
end
```

## Usage

`TODO: Fill this section out more completely`

This driver is effectively a wrapper around [Hyperkit](http://jeffshantz.github.io/hyperkit).  The quick and dirty answer (for now) is to refer to that and to the official [LXD REST API](https://github.com/lxc/lxd/blob/master/doc/rest-api.md) documentation to deduce the format of `driver_options` and `machine_options`.  There are some additional flags I introduce, but everything else gets sent straight down to the next layer.

Unless you've taken the time to install a trusted certificate on your LXD host, you will have to disable SSL verification like this, before you can use the REST API:

```ruby
with_driver 'lxd:hostname:8443', driver_options: { verify_ssl: false }
machine 'name' do
  driver 'lxd:hostname:8443'
  ...
end
```

As soon as I'm sure this gem is working as intended, I'll document more thoroughly.  Until then, use this driver at your own risk.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nexussw/chef-provisioning-lxd.  Make sure you sign off on all of your commits.

