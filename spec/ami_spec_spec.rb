require 'spec_helper'

describe AmiSpec do
  let(:amis) { {'web_server' => 'ami-1234abcd', 'db_server' => 'ami-1234abcd'} }
  let(:ec2_double) { instance_double(AmiSpec::AwsInstance) }
  let(:state) { double(name: 'running') }
  let(:test_result) { true }
  let(:server_spec_double) { double(run: test_result) }
  subject do
    described_class.run(
      amis: amis,
      specs: '/tmp/foobar',
      subnet_id: 'subnet-1234abcd',
      key_name: 'key',
      key_file: 'key.pem',
      aws_public_ip: false,
      aws_instance_type: 't2.micro',
      ssh_user: 'ubuntu',
      debug: false,
      ssh_retries: 30,
    )
  end

  describe '#run' do
    before do
      allow(described_class).to receive(:wait_for_ssh).and_return(true)
      allow(AmiSpec::AwsInstance).to receive(:start).and_return(ec2_double)
      allow(AmiSpec::ServerSpec).to receive(:new).and_return(server_spec_double)
      allow(ec2_double).to receive(:terminate).and_return(true)
      allow(ec2_double).to receive(:private_ip_address).and_return('127.0.0.1')
      allow_any_instance_of(Object).to receive(:sleep)
    end

    context 'successful tests' do
      it 'calls aws instance for each ami' do
        expect(AmiSpec::AwsInstance).to receive(:start).with(hash_including(role: 'web_server'))
        expect(AmiSpec::AwsInstance).to receive(:start).with(hash_including(role: 'db_server'))
        subject
      end

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'failed tests' do
      let(:test_result) { false }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end
  end

  describe '#wait_for_ssh' do
    subject do
      described_class.wait_for_ssh(ip: '127.0.0.1', user: 'ubuntu', key_file: 'key.pem', retries: 30)
    end

    it 'returns after one attempt if ssh connection succeeds' do
      expect(Net::SSH).to receive(:start)

      subject
    end

    context 'ssh fails' do
      before do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED, 'ssh failed')
      end

      it 'raises an exception' do
        expect{subject}.to raise_error(AmiSpec::InstanceConnectionTimeout)
      end

      it 'returns the last error' do
        expect(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED, 'some other error')
        expect{subject}.to raise_error(AmiSpec::InstanceConnectionTimeout, /ssh failed/)
      end
    end
  end
end
