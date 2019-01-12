require "chef/provisioning/transport"
require "nio/websocket"
require "socket"

class Chef
  module Provisioning
    module LXDDriver
      class Transport < Chef::Provisioning::Transport
        def initialize(nx_driver, nx_transport, config)
          @nx_driver = nx_driver
          @nx_transport = nx_transport
          @config = config
        end

        attr_reader :nx_transport, :nx_driver, :config

        # Execute a program on the remote host.
        #
        # == Arguments
        # command: command to run.  May be a shell-escaped string or a pre-split
        #          array containing [PROGRAM, ARG1, ARG2, ...].
        # options: hash of options, including but not limited to:
        #          :timeout => NUM_SECONDS - time to wait before program finishes
        #                      (throws an exception otherwise).  Set to nil or 0 to
        #                      run with no timeout.  Defaults to 15 minutes.
        #          :stream => BOOLEAN - true to stream stdout and stderr to the console.
        #          :stream => BLOCK - block to stream stdout and stderr to
        #                     (block.call(stdout_chunk, stderr_chunk))
        #          :stream_stdout => FD - FD to stream stdout to (defaults to IO.stdout)
        #          :stream_stderr => FD - FD to stream stderr to (defaults to IO.stderr)
        #          :read_only => BOOLEAN - true if command is guaranteed not to
        #                        change system state (useful for Docker)
        def execute(command, options = {})
          # if any of these keys are specified AND it doesn't have a :stream set to false/nil explicitly
          if options.keys.any? { |k| [:stream, :stream_stdout, :stream_stderr].include? k } && !(options.key?(:stream) && !options[:stream])
            sout = ""
            serr = ""
            # `capture: true` forces the block to stream rather than dump results at the end
            #   optimal performance (:capture unspecified) is LXD version dependant & potentially not streaming
            res = nx_driver.execute command, { timeout: DEFAULT_TIMEOUT, capture: true }.merge(options) do |stdout_chunk, stderr_chunk|
              # TODO: watch for double logging.
              #   LXD library does not double log to both the stream AND the execute result
              #   and I don't yet know what chefprov expects
              sout << stdout_chunk if stdout_chunk
              serr << stderr_chunk if stderr_chunk
              # base class helper func to digest the documented settings
              #   timeout is honored by the LXD lib
              #   and `command` can already be String or Array (via shellwords lib)
              stream_chunk options, stdout_chunk, stderr_chunk
            end
            res.tap do
              res.options[:capture_options][:stdout] = sout
              res.options[:capture_options][:stderr] = serr
            end
          else # streaming options were declined by the caller - 'log' it
            # `capture: true` in this context would still force streaming, but into the execute result, but with no streaming recipient
            #   suboptimal - let the library do its best
            # stdout & stderr will return in the execute result because a block is not supplied to execute
            #   chefprov can take em if it wants em
            nx_driver.execute command, { timeout: DEFAULT_TIMEOUT }.merge(options)
          end
        end

        def read_file(path)
          nx_transport.read_file path
        end

        def write_file(path, content)
          nx_transport.write_file path, content
        end

        def download_file(path, local_path)
          nx_transport.download_file path, local_path
        end

        def upload_file(local_path, path)
          nx_driver.upload_file local_path, path
        end

        def available?
          nx_driver.container_status(nx_transport.container_name) == "running" && nx_driver.wait_for(nx_driver.container_name, :cloud_init)
        end

        def make_url_available_to_remote(local_url)
          @forwards ||= {}
          uri = URI(local_url)
          uri_scheme = uri.scheme unless uri.scheme == "chefzero"
          host = Socket.getaddrinfo(uri.host, uri_scheme, nil, :STREAM)[0][3]
          new_uri = uri.clone

          # Purpose is to expose the local chefzero outside of the provisioner.  It only binds itself to localhost
          if host == "127.0.0.1" || host == "::1"

            new_uri.host = host_ip # TODO: make this react to a multihomed provisioner and provide the correct external interface

            # if host_ip.nil?  then we couldn't find an appropriate external interface
            return uri.to_s if new_uri.host.nil? || @forwards[new_uri.to_s]

            # using websocket proxy since it's already in our ecosystem
            # TODO: find exception thrown when port is in use and then retry with a random port
            @forwards[new_uri.to_s] = NIO::WebSocket.proxy "#{host}:#{uri.port}", address: new_uri.host, port: new_uri.port
          end

          new_uri.to_s
        end

        def disconnect
          return unless @forwards
          @forwards.each do |_url, srv|
            srv.close
          end
          @forwards = {}
        end

        protected

        def host_ip
          Socket.ip_address_list.select { |ai| (ai.ipv4? && !ai.ipv4_loopback?) || (ai.ipv6? && !ai.ipv6_loopback?) }[0]&.ip_address
        end
      end
    end
  end
end
