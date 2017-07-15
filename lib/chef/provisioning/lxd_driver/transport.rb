require 'chef/provisioning/transport'
require 'open3'
require 'nexussw/lxd/driver'
require 'tempfile'

class Chef
  module Provisioning
    module LXDDriver
      class LocalTransport < Chef::Provisioning::Transport
        def initialize(driver, container_name)
          @container_name = container_name
          @lxd = driver
        end

        def inner_exec(command_group, args, stream_options = {})
        end

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
        def execute(command, stream_options = {})
          mycommand = command
          mycommand = command.join(' ') if command.is_a?(Array)
          mycommand = "lxc exec #{@container_name} -- #{mycommand}"
          with_execute_timeout(stream_options) do
            Open3.popen3(mycommand) do |_stdin, stdout, stderr, th|
              loop do
                begin
                  stdout_chunk = stdout.read_nonblock 1024 unless stdout.eof?
                  stderr_chunk = stderr.read_nonblock 1024 unless stderr.eof?
                rescue IO::WaitReadable
                  IO.select [stdout, stderr]
                end
                stream_chunk stream_options, stdout_chunk, stderr_chunk
                return th.value if stdout.eof? && stderr.eof?
              end
            end
          end
        end

        def read_file(path)
          content = ''
          with_execute_timeout({}) do
            execute("cat #{path}", stream: ->(out_chunk, _err_chunk) { content += out_chunk if out_chunk })
          end
          content
        end

        def write_file(path, content)
          tfile = Tempfile.new(@container_name)
          tfile.write content
          tfile.close
          upload_file tfile.path, path
          tfile.unlink
        end

        def download_file(path, local_path)
          with_execute_timeout({}) do
            IO.popen("lxc file pull #{@container_name}#{path} #{local_path}").read
          end
        end

        def upload_file(local_path, path)
          with_execute_timeout({}) do
            IO.popen("lxc file push #{local_path} #{@container_name}#{path}").read
          end
        end

        def make_url_available_to_remote(_local_url)
          raise "make_url_available_to_remote not overridden on #{self.class}"
        end

        def disconnect
        end

        def available?
          @lxd.container_status(@container_name) == 'running'
        end

        # Config hash, including :log_level and :logger as keys
        def config
          {}
        end
      end
    end
  end
end
