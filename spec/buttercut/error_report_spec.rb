# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/error_report'

RSpec.describe ButterCut::ErrorReport do
  let(:repo_root) { @repo_root }
  let(:errors_dir) { File.join(repo_root, 'errors') }

  around do |example|
    Dir.mktmpdir('error-report-spec-') do |root|
      @repo_root = root
      example.run
    end
  end

  before do
    stub_const('ButterCut::ErrorReport::REPO_ROOT', repo_root)
    stub_const('ButterCut::ErrorReport::ERRORS_DIR', errors_dir)
    stub_const('ButterCut::ErrorReport::LEDGER_FILE', File.join(errors_dir, '.sent_fingerprints.json'))
    stub_const('ButterCut::ErrorReport::CONSENT_FILE', File.join(repo_root, '.buttercut_error_reporting'))
    stub_const('ButterCut::ErrorReport::LICENSE_FILE', File.join(repo_root, '.buttercut_pro_license'))
  end

  def error_with_backtrace(message = 'boom', klass: RuntimeError, frames: nil)
    error = klass.new(message)
    error.set_backtrace(frames || ["#{repo_root}/lib/buttercut/export_core.rb:42:in `build_xml'"])
    error
  end

  def dumps = Dir[File.join(errors_dir, '*.json')]

  describe '.fingerprint' do
    it 'is stable across line-number changes in the same frame' do
      a = error_with_backtrace(frames: ["#{repo_root}/lib/buttercut/export_core.rb:42:in `build_xml'"])
      b = error_with_backtrace(frames: ["#{repo_root}/lib/buttercut/export_core.rb:99:in `build_xml'"])

      expect(described_class.fingerprint(a, action: 'export'))
        .to eq(described_class.fingerprint(b, action: 'export'))
    end

    it 'differs by error class, frame, and action' do
      error = error_with_backtrace
      base = described_class.fingerprint(error, action: 'export')

      expect(described_class.fingerprint(error, action: 'transcribe')).not_to eq(base)
      expect(described_class.fingerprint(error_with_backtrace(klass: TypeError), action: 'export')).not_to eq(base)
      other_frame = error_with_backtrace(frames: ["#{repo_root}/lib/buttercut/fcpx_core.rb:10:in `emit'"])
      expect(described_class.fingerprint(other_frame, action: 'export')).not_to eq(base)
    end

    it 'prefers the topmost in-repo frame over stdlib frames' do
      error = error_with_backtrace(frames: [
        "/usr/lib/ruby/3.3.0/json/common.rb:1:in `parse'",
        "#{repo_root}/lib/buttercut/library.rb:7:in `load'"
      ])
      in_repo_only = error_with_backtrace(frames: ["#{repo_root}/lib/buttercut/library.rb:9:in `load'"])

      expect(described_class.fingerprint(error, action: 'summary'))
        .to eq(described_class.fingerprint(in_repo_only, action: 'summary'))
    end
  end

  describe '.capture!' do
    it 'writes a dump and prints the banner for an unexpected error' do
      path = nil
      expect { path = described_class.capture!(error_with_backtrace, action: 'export') }
        .to output(/BUTTERCUT ERROR CAPTURED: errors\//).to_stderr

      expect(dumps).to eq([path])
      report = JSON.parse(File.read(path))
      expect(report).to include('schema_version' => 1, 'source' => 'cli')
      expect(report['report_uuid']).to match(/\A\h{8}-/)
      expect(report['buttercut']).to eq('version' => ButterCut::VERSION, 'edition' => ButterCut::EDITION.to_s)
      expect(report['error']).to include('class' => 'RuntimeError', 'action' => 'export')
      expect(report['error']['backtrace'].first).to eq("lib/buttercut/export_core.rb:42:in `build_xml'")
    end

    it 'is a no-op for expected error classes' do
      [ArgumentError.new('bad input'), ButterCut::UserError.new('nope'),
       MediaTools::MissingBinary.new('no ffmpeg')].each do |error|
        error.set_backtrace([])
        expect { described_class.capture!(error, action: 'export') }.not_to output.to_stderr
      end

      expect(dumps).to be_empty
    end

    it 'matches expected classes by name for subclasses too' do
      subclass = Class.new(ArgumentError)
      expect(described_class.expected?(subclass.new)).to be true
    end

    it 'is a no-op in developer checkouts unless forced' do
      FileUtils.touch(File.join(repo_root, '.buttercut_mode'))

      expect { described_class.capture!(error_with_backtrace, action: 'export') }.not_to output.to_stderr
      expect(dumps).to be_empty

      ENV['BUTTERCUT_FORCE_ERROR_CAPTURE'] = '1'
      expect { described_class.capture!(error_with_backtrace, action: 'export') }
        .to output(/BUTTERCUT ERROR CAPTURED/).to_stderr
      expect(dumps.length).to eq(1)
    ensure
      ENV.delete('BUTTERCUT_FORCE_ERROR_CAPTURE')
    end

    it 'never raises out of its own failure' do
      allow(described_class).to receive(:write_dump).and_raise('disk full')

      expect(described_class.capture!(error_with_backtrace, action: 'export')).to be_nil
    end

    it 'scrubs the home directory from message and backtrace' do
      home = Dir.home
      error = error_with_backtrace("ffprobe failed for #{home}/footage/wedding.mov",
                                   frames: ["#{repo_root}/lib/buttercut/library.rb:1:in `probe'", "#{home}/other.rb:2:in `x'"])
      path = nil
      expect { path = described_class.capture!(error, action: 'summary') }.to output.to_stderr

      raw = File.read(path)
      expect(raw).not_to include(home)
      expect(raw).to include('~/footage/wedding.mov')
    end
  end

  describe '.consent' do
    it 'defaults to ask, persists always/never, and rejects junk' do
      expect(described_class.consent).to eq('ask')

      described_class.consent = 'always'
      expect(described_class.consent).to eq('always')

      described_class.consent = 'never'
      expect(described_class.consent).to eq('never')

      expect { described_class.consent = 'maybe' }.to raise_error(ButterCut::UserError, /must be one of/)

      File.write(File.join(repo_root, '.buttercut_error_reporting'), "gibberish\n")
      expect(described_class.consent).to eq('ask')
    end
  end

  describe '.new_agent_report' do
    it 'drafts a source=agent report with a summary-seeded fingerprint' do
      path = described_class.new_agent_report('export', 'Premiere rejects exported XML')
      report = JSON.parse(File.read(path))

      expect(report).to include('source' => 'agent')
      expect(report['error']).to include('class' => nil, 'message' => 'Premiere rejects exported XML', 'action' => 'export')

      again = JSON.parse(File.read(described_class.new_agent_report('export', 'premiere rejects exported xml')))
      expect(again['fingerprint']).to eq(report['fingerprint'])
    end

    it 'requires a summary' do
      expect { described_class.new_agent_report('export', ' ') }.to raise_error(ButterCut::UserError, /--summary/)
    end
  end

  describe '.probe' do
    it 'returns a scrubbed probe_error hash instead of raising' do
      result = described_class.probe('/nowhere/secret-client-name/missing.mov')

      expect(result['file']).to eq('missing.mov')
      expect(result).to have_key('probe_error')
    end
  end

  describe '.send_report' do
    let(:success) { instance_double(Net::HTTPCreated, code: '201', body: '{"status":"accepted"}') }

    def write_reviewed_report
      described_class.capture!(error_with_backtrace, action: 'export')
      dumps.first
    end

    before { allow(described_class).to receive(:warn) } # silence capture!'s banner

    it 'raises UserError for a missing file or missing keys' do
      expect { described_class.send_report('/nope.json') }.to raise_error(ButterCut::UserError, /not found/)

      path = File.join(repo_root, 'bad.json')
      File.write(path, JSON.generate('fingerprint' => 'abc'))
      expect { described_class.send_report(path) }.to raise_error(ButterCut::UserError, /report_uuid/)
    end

    it 'skips when consent is never' do
      described_class.consent = 'never'
      result = described_class.send_report(write_reviewed_report)

      expect(result['outcome']).to eq('skipped')
    end

    it 'demands approval when consent is ask' do
      result = described_class.send_report(write_reviewed_report)

      expect(result['outcome']).to eq('needs_approval')
    end

    it 'sends with approval, records the ledger, and dedupes the second attempt' do
      allow(described_class).to receive(:post).and_return(success)
      path = write_reviewed_report

      result = described_class.send_report(path, user_approved: true)
      expect(result).to include('outcome' => 'sent', 'server' => { 'status' => 'accepted' })

      expect(described_class.send_report(path, user_approved: true)['outcome']).to eq('already_reported')
      expect(described_class).to have_received(:post).once
    end

    it 'sends without approval when consent is always' do
      allow(described_class).to receive(:post).and_return(success)
      described_class.consent = 'always'

      expect(described_class.send_report(write_reviewed_report)['outcome']).to eq('sent')
    end

    it 'reports failure without raising when the endpoint is unreachable or unhappy' do
      path = write_reviewed_report
      described_class.consent = 'always'

      allow(described_class).to receive(:post).and_raise(SocketError)
      expect(described_class.send_report(path)['outcome']).to eq('failed')

      allow(described_class).to receive(:post)
        .and_return(instance_double(Net::HTTPTooManyRequests, code: '429', body: ''))
      result = described_class.send_report(path)
      expect(result['outcome']).to eq('failed')
      expect(result['note']).to include('429')
      expect(described_class.list.first['reported']).to be false
    end

    it 'rejects oversize reports before posting' do
      path = write_reviewed_report
      report = JSON.parse(File.read(path))
      report['narrative'] = 'x' * (ButterCut::ErrorReport::MAX_REPORT_BYTES + 1)
      File.write(path, JSON.generate(report))

      expect { described_class.send_report(path, user_approved: true) }
        .to raise_error(ButterCut::UserError, /trim narrative/)
    end
  end

  describe '.list' do
    it 'reports each dump with its sent status' do
      allow(described_class).to receive(:warn)
      described_class.capture!(error_with_backtrace, action: 'export')

      list = described_class.list
      expect(list.length).to eq(1)
      expect(list.first['reported']).to be false
      expect(list.first['file']).to start_with('errors/')
    end
  end

  describe '.license_headers' do
    it 'is empty without a license file (core installs)' do
      expect(described_class.send(:license_headers)).to eq({})
    end

    it 'reads the Pro key=value license file into the auth headers' do
      File.write(File.join(repo_root, '.buttercut_pro_license'),
                 "email=ada@example.com\nlicense_key=BC-KEY-1\n")

      expect(described_class.send(:license_headers)).to eq(
        'X-Buttercut-Email' => 'ada@example.com',
        'X-Buttercut-License-Key' => 'BC-KEY-1'
      )
    end
  end
end
