require 'spec_helper'

# Prerequisites: 
#   - LXD must be installed locally and listening on the default port
#   - must have cert and key installed in .config/lxd/ by default,
#       or otherwise specified in this constructor

describe 'Chef Provisioning LXD Driver' do
  let(:test_name) { 'lxd-chef-driver-test' }
  let(:test_name2) { 'lxd-chef-driver-test2' }
  let(:host_address) { 'https://localhost:8443' }
  let(:lxd) { NexusSW::LXD::Driver.new host_address, verify_ssl: false }
  let(:transport) { Chef::Provisioning::LXDDriver::LocalTransport.new lxd, test_name2 }
  context 'Core Implementation' do
    it 'has a version number' do
      expect(NexusSW::LXD::VERSION).not_to be nil
    end

    it 'detects a missing container' do
      expect(lxd.container_exists?('idontexist')).not_to be true
    end

    it 'fails creating a container asynchronously with bad options' do
      expect{ lxd.create_container('iwontexist', alias: 'ubububuntu-idontexist')}.to raise_error(Hyperkit::InternalServerError)
    end

    it 'creates a container' do
      expect(lxd.create_container(test_name, alias: 'ubuntu-14.04')).to eq test_name
      expect(lxd.create_container(test_name2, alias: 'ubuntu-14.04')).to eq test_name2
    end

    it 'detects an existing container' do
      expect(lxd.container_exists?(test_name)).to be true
    end

    it 'can start a container asynchronously' do
      expect(lxd.start_container_async(test_name))
    end

    it 'can stop a container that is not yet running' do
      lxd.stop_container test_name
      expect(lxd.container_status(test_name)).to eq 'stopped'
    end

    it 'can start a container normally' do
      lxd.start_container test_name2
      expect(lxd.container_status(test_name2)).to eq 'running'
    end

    it 'can execute a command in the container' do
      expect{ transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
    end

    it 'remaps localhost to an adapter ip' do
      expect(transport.make_url_available_to_remote('chefzero://localhost:1234')).not_to include('localhost')
      expect(transport.make_url_available_to_remote('chefzero://127.0.0.1:1234')).not_to include('127.0.0.1')
    end

    it 'can output to a file' do
      expect{ transport.write_file('/tmp/somerandomfile.tmp', 'some random content') }.not_to raise_error
    end

    it 'can upload a file' do
      expect{ transport.upload_file('/etc/passwd', '/tmp/passwd.tmp') }.not_to raise_error
    end

    it 'can download a file' do
      expect{ transport.download_file('/etc/group', '/tmp/rspectest.tmp') }.not_to raise_error
    end

    it 'can read a file' do
      expect(transport.read_file('/tmp/passwd.tmp')).to include('root:')
    end

    it 'can delete a running container' do
      lxd.delete_container test_name2
      expect(lxd.container_exists?(test_name2)).to be false
      lxd.delete_container test_name
    end
  end
end
