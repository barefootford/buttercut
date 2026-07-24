require 'spec_helper'
require_relative '../../lib/buttercut/keep_awake'

RSpec.describe KeepAwake do
  describe '.start' do
    it 'spawns the platform helper detached and returns its PID' do
      allow(Platform).to receive(:keep_awake_argv).and_return(['caffeinate', '-i'])
      allow(Process).to receive(:spawn).and_return(4321)
      allow(Process).to receive(:detach)

      expect(KeepAwake.start).to eq(4321)
      expect(Process).to have_received(:detach).with(4321)
    end

    # A helper nobody stops shouldn't cost the user a machine that never sleeps.
    it 'gives caffeinate its own deadline' do
      allow(Platform).to receive(:keep_awake_argv).and_return(['caffeinate', '-i'])
      allow(Process).to receive(:detach)
      allow(Process).to receive(:spawn).and_return(1)

      KeepAwake.start

      expect(Process).to have_received(:spawn)
        .with('caffeinate', '-i', '-t', KeepAwake::MAX_SECONDS.to_s, hash_including(:out))
    end

    it 'is nil where the platform has no keep-awake mechanism' do
      allow(Platform).to receive(:keep_awake_argv).and_return(nil)

      expect(KeepAwake.start).to be_nil
    end

    # Processing footage matters more than holding sleep off, so a missing
    # helper is a nil, not an exception.
    it 'is nil when the helper cannot be spawned' do
      allow(Platform).to receive(:keep_awake_argv).and_return(['caffeinate', '-i'])
      allow(Process).to receive(:spawn).and_raise(Errno::ENOENT)

      expect(KeepAwake.start).to be_nil
    end
  end

  describe '.stop' do
    it 'kills the PID it is given' do
      allow(Process).to receive(:kill)

      expect(KeepAwake.stop('4321')).to be(true)
      expect(Process).to have_received(:kill).with('KILL', 4321)
    end

    # This runs in cleanup positions, where raising would bury whatever
    # actually went wrong.
    it 'shrugs off an empty, malformed or already-dead PID' do
      expect(KeepAwake.stop('')).to be(false)
      expect(KeepAwake.stop(nil)).to be(false)
      expect(KeepAwake.stop('not-a-pid')).to be(false)

      allow(Process).to receive(:kill).and_raise(Errno::ESRCH)
      expect(KeepAwake.stop('4321')).to be(false)
    end
  end
end
