require 'chef/provisioning/lxd_driver/transport'
require 'pp'

class Chef
  module Provisioning
    module LXDDriver
      class Transport
        class Remote < Transport
          def initialize(driver, container_name, config = {})
            super driver, container_name, config
            @hk = driver.hk
          end

          # I suspect this is going to log all output and we won't be able to get any of it until the command is done
          # which will suck for long running processes such as the initial chef-client run/converge.
          # TODO: someday.  Rewrite this to use websockets - unsupported by hyperkit, but available on the rest api.
          # I bet we can stream the websockets
          # Opening this can of worms 'might' lead us to not using hyperkit at all - TBD
          def execute(command, options = {})
            with_streamoptions(options) do |stream_options|
              retval = hk.execute(container_name, command, record_output: true)
              pp '', '*** hk.execute ***', retval, '**********'
              raise 'check pp output'
              stream_chunk stream_options, stdout_chunk, stderr_chunk
              return LXDExecuteResult.new(command, stream_options, th.value.exitstatus) # if th.value.exited? && stdout.eof? && stderr.eof?
            end
          end

          def read_file(path)
            hk.read_file container_name, path
          end

          def write_file(path, content)
            hk.write_file container_name, path, content: content
          end

          def download_file(path, local_path)
            hk.pull_file container_name, path, local_path
          end

          def upload_file(local_path, path)
            hk.push_file local_path, container_name, path
          end

          def host_ip
            # is there a way to get this default adapter info via Socket api?  or would it be even dirtier?...
            # or is not binding to an ip reliable in a multi-homed configuration?

            # local = Local.new config
            # res = local.execute("bash -c \"ip r | sed -n '/^default /s/^.*dev \(.*\)$/\1/p'\"")
            # res.error!
            # ifaddrs = Socket.getifaddrs.select do |iface|
            #   iface.name == res.stdout && iface.addr.ip?
            # end
            # raise "Unable to get the IP address of the default Host Adapter: #{res.stdout}" if ifaddrs.empty?
            # ifaddrs.first.addr.ip_address

            # A couple of simple tests indicate that a default server socket bind should do the trick
            # we'll do the 'default' interface trick above if this doesn't work in the field
            nil
          end
        end
      end
    end
  end
end
