# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/report'

RSpec.describe ButterCut::Report do
  let(:repo_root) { @repo_root }
  let(:reports_dir) { File.join(repo_root, 'reports') }

  around do |example|
    Dir.mktmpdir('report-spec-') do |root|
      @repo_root = root
      example.run
    end
  end

  before do
    stub_const('ButterCut::Report::REPO_ROOT', repo_root)
    stub_const('ButterCut::Report::REPORTS_DIR', reports_dir)
    stub_const('ButterCut::Report::LEDGER_FILE', File.join(reports_dir, '.sent_fingerprints.json'))
    stub_const('ButterCut::Report::CONSENT_FILE', File.join(repo_root, '.buttercut_reporting'))
    stub_const('ButterCut::Report::LICENSE_FILE', File.join(repo_root, '.buttercut_pro_license'))
  end

  def error_with_backtrace(message = 'boom', klass: RuntimeError, frames: nil)
    error = klass.new(message)
    error.set_backtrace(frames || ["#{repo_root}/lib/buttercut/export_core.rb:42:in `build_xml'"])
    error
  end

  def dumps = Dir[File.join(reports_dir, '*.json')]

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
        .to output(%r{BUTTERCUT ERROR CAPTURED: reports/}).to_stderr

      expect(dumps).to eq([path])
      report = JSON.parse(File.read(path))
      expect(report).to include('schema_version' => 1, 'source' => 'cli', 'kind' => 'bug',
                                'title' => 'RuntimeError during export')
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

      File.write(File.join(repo_root, '.buttercut_reporting'), "gibberish\n")
      expect(described_class.consent).to eq('ask')
    end
  end

  describe '.new_bug_report' do
    it 'drafts a source=agent bug with a summary-seeded fingerprint and title' do
      path = described_class.new_bug_report('export', 'Premiere rejects exported XML')
      report = JSON.parse(File.read(path))

      expect(report).to include('kind' => 'bug', 'source' => 'agent', 'title' => 'Premiere rejects exported XML')
      expect(report['error']).to include('class' => nil, 'message' => 'Premiere rejects exported XML', 'action' => 'export')

      again = JSON.parse(File.read(described_class.new_bug_report('export', 'premiere rejects exported xml')))
      expect(again['fingerprint']).to eq(report['fingerprint'])
    end

    it 'requires a summary' do
      expect { described_class.new_bug_report('export', ' ') }.to raise_error(ButterCut::UserError, /--summary/)
    end
  end

  describe '.new_feature_request' do
    # The server keys triage off kind/source/title and expects error to be null
    # for a feature — see spec/requests/api/v1/buttercut_reports_spec.rb in TubeSalt.
    it 'drafts the shape the reports endpoint stores as a feature' do
      path = described_class.new_feature_request('Support multicam angles in exports')
      report = JSON.parse(File.read(path))

      expect(report).to include(
        'kind' => 'feature', 'source' => 'user', 'error' => nil,
        'title' => 'Support multicam angles in exports'
      )
      expect(report['report_uuid']).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      expect(report['fingerprint']).to match(/\A\h{8,64}\z/)
      expect(File.basename(path)).to include('-feature-')
    end

    it 'collapses the same request asked in the same words' do
      first = JSON.parse(File.read(described_class.new_feature_request('Add vertical exports')))
      again = JSON.parse(File.read(described_class.new_feature_request('  add vertical exports  ')))

      expect(again['fingerprint']).to eq(first['fingerprint'])
      expect(again['report_uuid']).not_to eq(first['report_uuid'])
    end

    it 'clips an overlong title to what the server stores' do
      path = described_class.new_feature_request('x' * 400)

      expect(JSON.parse(File.read(path))['title'].length).to eq(ButterCut::Report::TITLE_LIMIT)
    end

    it 'requires a title' do
      expect { described_class.new_feature_request(' ') }.to raise_error(ButterCut::UserError, /--title/)
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

    # The path is the whole contract with TubeSalt: config/routes.rb mounts
    # api/v1/buttercut_reports, and a wrong path just 404s at send time.
    it 'posts to the ButterCut reports endpoint' do
      described_class.consent = 'always'
      http = instance_double(Net::HTTP, :open_timeout= => nil, :read_timeout= => nil, :use_ssl= => nil)
      allow(Net::HTTP).to receive(:new).with('tubesalt.com', 443).and_return(http)
      allow(http).to receive(:request) { |req| @request = req }.and_return(success)

      expect(described_class.send_report(write_reviewed_report)['outcome']).to eq('sent')
      expect(@request.path).to eq('/api/v1/buttercut_reports')
      expect(@request['Content-Type']).to eq('application/json')
    end

    it 'attaches the Pro license headers when the install has a license' do
      described_class.consent = 'always'
      File.write(File.join(repo_root, '.buttercut_pro_license'), "email=ada@example.com\nlicense_key=BC-KEY-1\n")
      http = instance_double(Net::HTTP, :open_timeout= => nil, :read_timeout= => nil, :use_ssl= => nil)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:request) { |req| @request = req }.and_return(success)

      described_class.send_report(write_reviewed_report)

      expect(@request['X-Buttercut-Email']).to eq('ada@example.com')
      expect(@request['X-Buttercut-License-Key']).to eq('BC-KEY-1')
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
      report['narrative'] = 'x' * (ButterCut::Report::MAX_REPORT_BYTES + 1)
      File.write(path, JSON.generate(report))

      expect { described_class.send_report(path, user_approved: true) }
        .to raise_error(ButterCut::UserError, /trim narrative/)
    end
  end

  describe '.list' do
    it 'reports each draft with its kind, title, and sent status' do
      allow(described_class).to receive(:warn)
      described_class.capture!(error_with_backtrace, action: 'export')
      described_class.new_feature_request('Support multicam angles in exports')

      list = described_class.list
      expect(list.length).to eq(2)
      expect(list.map { |entry| entry['kind'] }).to contain_exactly('bug', 'feature')
      expect(list.map { |entry| entry['reported'] }).to all(be false)
      expect(list.map { |entry| entry['file'] }).to all(start_with('reports/'))
      expect(list.map { |entry| entry['title'] })
        .to contain_exactly('RuntimeError during export', 'Support multicam angles in exports')
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
