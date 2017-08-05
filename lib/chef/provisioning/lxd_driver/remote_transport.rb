require 'chef/provisioning/lxd_driver/lxd_transport'

class Chef
  module Provisioning
    module LXDDriver
      class RemoteTransport < LXDTransport
        def initialize(driver, container_name, config = {})
          super driver, container_name, config
        end

        def execute(command, options = {})
          # try to factor out dupe code with localtransport
        end

        def read_file(path)
        end

        def write_file(path, content)
        end

        def download_file(path, local_path)
        end

        def upload_file(local_path, path)
        end

        def available?
          lxd.container_status(container_name) == 'running'
        end
      end
    end
  end
end
