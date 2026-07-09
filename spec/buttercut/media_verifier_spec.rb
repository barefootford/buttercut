# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/buttercut/media_verifier'

# All examples run inside a tmpdir that stands in for `/Volumes` (injected via
# `volumes_root:`), and most inject `root_dev:` so phantom detection is
# deterministic: the "boot device" is always the dev of the tmp files we create.
# One example omits root_dev on purpose, pinning the production default to the
# device volumes_root itself lives on.
RSpec.describe MediaVerifier do
  around do |example|
    Dir.mktmpdir('media-verifier-') do |root|
      @volumes = root
      example.run
    end
  end

  # The device the tmpdir sits on — stand-in for the internal boot disk.
  let(:root_dev) { File.stat(@volumes).dev }

  def vol(*parts) = File.join(@volumes, *parts)

  # Create a file (and its parent dirs) at <volumes>/<rel>, return the path.
  def touch(rel)
    path = vol(rel)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
    path
  end

  def verify(paths, **opts)
    MediaVerifier.new(paths, root_dev: root_dev, volumes_root: @volumes, **opts)
  end

  # Pretend the boot disk is elsewhere, so the tmp volumes read as real external
  # mounts (by default they'd all sit on root_dev and read as squatter folders).
  def verify_external(paths) = verify(paths, root_dev: root_dev + 1)

  describe 'status' do
    it 'reports an existing file on a non-root device as ok' do
      path = touch('Andrew SSD/CAC/C2407.MP4')
      report = verify_external([path]).report

      expect(report['media'].first['status']).to eq('ok')
      expect(report['ok_count']).to eq(1)
    end

    it 'reports a nonexistent path as missing' do
      report = verify([vol('Andrew SSD/gone.MP4')]).report

      expect(report['media'].first['status']).to eq('missing')
      expect(report['missing_count']).to eq(1)
    end

    it 'derives the default boot-device baseline from volumes_root itself, not `/`' do
      # On APFS `/` can be a sealed snapshot on a different device than the
      # Data volume /Volumes is firmlinked into; keying off `/` would miss
      # squatter folders entirely. No root_dev injected — this exercises the
      # production default against a squatter dir sharing volumes_root's device.
      path = touch('Andrew SSD/CAC/C2407.MP4')

      report = MediaVerifier.new([path], volumes_root: @volumes).report

      expect(report['media'].first['status']).to eq('phantom')
      expect(report['phantom_volumes']).to eq([vol('Andrew SSD')])
    end

    it 'reports a file in a leftover boot-disk folder as phantom' do
      path = touch('Andrew SSD/CAC/C2407.MP4') # the volume root is a real dir on root_dev

      report = verify([path]).report

      expect(report['media'].first['status']).to eq('phantom')
      expect(report['phantom_count']).to eq(1)
      expect(report['phantom_volumes']).to eq([vol('Andrew SSD')])
    end

    it 'never flags a symlinked volume root as phantom, even on the root device' do
      # `/Volumes/Macintosh HD -> /` is a symlink; a legit path under it resolves
      # to the boot device but must read ok, not phantom.
      real = Dir.mktmpdir('real-boot-')
      FileUtils.mkdir_p(File.join(real, 'Users/andrew'))
      FileUtils.touch(File.join(real, 'Users/andrew/footage.mov'))
      File.symlink(real, vol('Macintosh HD'))

      report = verify([vol('Macintosh HD/Users/andrew/footage.mov')]).report

      expect(report['media'].first['status']).to eq('ok')
      expect(report['phantom_volumes']).to be_empty
    ensure
      FileUtils.remove_entry(real)
    end

    it 'treats a non-/Volumes path only by existence (never phantom)' do
      Dir.mktmpdir do |elsewhere|
        present = File.join(elsewhere, 'a.mov')
        FileUtils.touch(present)
        report = verify([present, File.join(elsewhere, 'gone.mov')]).report

        expect(report['media'].map { |m| m['status'] }).to eq(%w[ok missing])
        expect(report['suggested_relinks']).to be_empty
      end
    end
  end

  describe 'suggested_relinks' do
    # Suggestion targets must be real mounts, hence verify_external throughout.
    it 'suggests the sibling volume when every miss agrees' do
      touch('Andrew SSD 1/CAC/C2407.MP4')
      touch('Andrew SSD 1/CAC/C2408.MP4')
      report = verify_external([vol('Andrew SSD/CAC/C2407.MP4'), vol('Andrew SSD/CAC/C2408.MP4')]).report

      expect(report['suggested_relinks']).to eq(
        [{ 'from' => vol('Andrew SSD'), 'to' => vol('Andrew SSD 1'), 'resolves' => 2 }]
      )
    end

    it 'makes no suggestion when the tail exists under two volumes (ambiguous)' do
      touch('DriveA/CAC/C2407.MP4')
      touch('DriveB/CAC/C2407.MP4')
      report = verify_external([vol('Andrew SSD/CAC/C2407.MP4')]).report

      expect(report['suggested_relinks']).to be_empty
    end

    it 'makes no suggestion when the misses disagree on a target' do
      touch('Andrew SSD 1/a/x.MP4') # a/x.MP4 only under "Andrew SSD 1"
      touch('Andrew SSD 2/b/y.MP4') # b/y.MP4 only under "Andrew SSD 2"
      report = verify_external([vol('Andrew SSD/a/x.MP4'), vol('Andrew SSD/b/y.MP4')]).report

      expect(report['suggested_relinks']).to be_empty
    end

    it 'skips a symlinked volume when probing for a sibling' do
      # A `Macintosh HD -> /`-style symlink child must not manufacture a hit.
      real = Dir.mktmpdir('real-boot-')
      FileUtils.mkdir_p(File.join(real, 'CAC'))
      FileUtils.touch(File.join(real, 'CAC/C2407.MP4')) # exists via the symlink
      File.symlink(real, vol('Macintosh HD'))

      report = verify_external([vol('Andrew SSD/CAC/C2407.MP4')]).report

      expect(report['suggested_relinks']).to be_empty
    ensure
      FileUtils.remove_entry(real)
    end

    it 'skips an unreadable /Volumes entry instead of dropping every suggestion' do
      touch('Andrew SSD 1/CAC/C2407.MP4')
      flaky = vol('Flaky NAS')
      FileUtils.mkdir_p(flaky)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(flaky).and_raise(Errno::EIO)

      report = verify_external([vol('Andrew SSD/CAC/C2407.MP4')]).report

      expect(report['suggested_relinks']).to eq(
        [{ 'from' => vol('Andrew SSD'), 'to' => vol('Andrew SSD 1'), 'resolves' => 1 }]
      )
    end

    it 'never suggests a boot-device squatter folder as a relink target' do
      # The missing file's tail exists — but inside another leftover folder on
      # the boot disk (default root_dev), not on a real mount. Suggesting it
      # would point the library at a squatter copy.
      touch('Rescued Copies/CAC/C2407.MP4')
      report = verify([vol('Andrew SSD/CAC/C2407.MP4')]).report

      expect(report['suggested_relinks']).to be_empty
    end

    it 'never suggests a relink for a phantom file (divergent-copy guard)' do
      touch('Andrew SSD/CAC/C2407.MP4')   # phantom: real folder on root_dev
      touch('Andrew SSD 1/CAC/C2407.MP4') # a sibling copy exists
      report = verify([vol('Andrew SSD/CAC/C2407.MP4')]).report

      expect(report['media'].first['status']).to eq('phantom')
      expect(report['suggested_relinks']).to be_empty
    end
  end

  describe '#problem_summary' do
    it 'names the shared volume when every problem is under one prefix' do
      summary = verify([vol('Andrew SSD/a.MP4'), vol('Andrew SSD/b.MP4')]).problem_summary(total: 3)

      expect(summary).to include('2 of 3 source files')
      expect(summary).to include("under #{vol('Andrew SSD')}/")
    end

    it 'drops the shared-volume clause when prefixes differ' do
      summary = verify([vol('DriveA/a.MP4'), vol('DriveB/b.MP4')]).problem_summary(total: 2)

      expect(summary).not_to include('all under')
    end

    it 'calls out a phantom volume as a leftover folder on the internal disk' do
      path = touch('Andrew SSD/CAC/C2407.MP4') # real dir on root_dev → phantom

      summary = verify([path]).problem_summary(total: 1)

      expect(summary).to include("#{vol('Andrew SSD')} is a leftover folder on this Mac's internal disk")
    end
  end

  describe '#ok?' do
    it 'is true only when every path resolves cleanly' do
      present = touch('Andrew SSD/a.MP4')
      expect(verify_external([present]).ok?).to be(true)
      expect(verify_external([present, vol('Andrew SSD/gone.MP4')]).ok?).to be(false)
    end
  end
end
