require 'chef/provisioning/lxd_driver/driver'

Chef::Provisioning.register_driver_class('lxd', Chef::Provisioning::LXDDriver::Driver)
