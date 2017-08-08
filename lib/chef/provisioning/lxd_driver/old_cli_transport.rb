require 'chef/mash'
require 'open3'
require 'nexussw/lxd/driver'
require 'tempfile'
require 'socket'
require 'stringio'
require 'bundler'
require 'surro-gate/lib/surro-gate/proxy'
require 'chef/provisioning/lxd_driver/lxd_transport'

class Chef
  module Provisioning
    module LXDDriver
      class CLITransport < LXDTransport
        # config = hash, including :log_level and :logger as keys
        def initialize(driver, container_name, config = {})
          super driver, container_name, config
          @container_name = super.container_name
        end

        attr_accessor :container_name

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
          stream_options = options.clone
          mycommand = command
          mycommand = command.join(' ') if command.is_a?(Array)
          subcommand = stream_options[:subcommand] || "exec #{container_name} --"
          mycommand = "lxc #{subcommand} #{mycommand}"
          unless stream_options[:stream]
            stream_options[:stdout] = '' # StringIO.new
            stream_options[:stderr] = '' # StringIO.new
            stream_options[:stream] = lambda do |sout, serr|
              stream_options[:stdout] += sout if sout
              stream_options[:stderr] += serr if serr
            end
          end

          with_execute_timeout(stream_options) do
            Open3.popen3(mycommand) do |_stdin, stdout, stderr, th|
              streams = [stdout, stderr]
              loop do
                begin
                  stdout_chunk = stdout.read_nonblock 1024 unless stdout.eof?
                rescue IO::WaitReadable
                  IO.select streams, nil, streams, 1
                end
                begin
                  stderr_chunk = stderr.read_nonblock 1024 unless stderr.eof?
                rescue IO::WaitReadable
                  IO.select streams, nil, streams, 1 unless stdout_chunk
                end
                stream_chunk stream_options, stdout_chunk, stderr_chunk
                return LXDExecuteResult.new(mycommand, stream_options[:stdout], stream_options[:stderr], th.value.exitstatus) if th.value.exited? && stdout.eof? && stderr.eof?
              end
            end
          end
        end

        def read_file(path)
          tfile = Tempfile.new(container_name)
          tfile.close
          retval = execute("#{container_name}#{path} #{tfile.path}", subcommand: 'file pull')
          return '' if retval.exitstatus == 1
          retval.error!
          tfile.open
          content = tfile.read
          tfile.close

          content
        ensure
          tfile.unlink
        end

        def write_file(path, content)
          tfile = Tempfile.new(container_name)
          tfile.write content
          tfile.close
          upload_file tfile.path, path
        ensure
          tfile.unlink
        end

        def download_file(path, local_path)
          execute("#{container_name}#{path} #{local_path}", subcommand: 'file pull').error!
        end

        def upload_file(local_path, path)
          execute("#{local_path} #{container_name}#{path}", subcommand: 'file push').error!
        end

        def available?
          lxd.container_status(container_name) == 'running'
        end
      end
    end
  end
end
