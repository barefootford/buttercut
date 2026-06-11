require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'date'
require 'fileutils'

RSpec.describe 'Migration scripts' do
  let(:libraries_root) { @libraries_root }

  around do |example|
    Dir.mktmpdir('migration-spec-') do |root|
      @libraries_root = root
      example.run
    end
  end

  before { allow($stdout).to receive(:puts) }

  def library_dir(name = 'test-lib')
    File.join(libraries_root, name)
  end

  def library_yaml_path(name = 'test-lib')
    File.join(library_dir(name), 'library.yaml')
  end

  def write_yaml(content, name: 'test-lib')
    dir = library_dir(name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'library.yaml'), content, encoding: 'UTF-8')
  end

  def read_yaml(name = 'test-lib')
    YAML.load(File.read(library_yaml_path(name), encoding: 'UTF-8'), permitted_classes: [Date, Time, Symbol])
  end

  def read_raw(name = 'test-lib')
    File.read(library_yaml_path(name), encoding: 'UTF-8')
  end

  # ─── 001: transcript_path → transcript, remove file_size_mb ───

  describe '001_migrate_0.2_to_0.3' do
    before(:context) { load File.expand_path('../scripts/001_migrate_0.2_to_0.3.rb', __dir__) }

    def migrate(name = 'test-lib')
      migrate_library(library_yaml_path(name))
    end

    it 'renames transcript_path to transcript with just the filename' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /Users/andrew/footage/DJI_0001.mov
            transcript_path: "/Users/andrew/footage/transcripts/DJI_0001.json"
            duration: "00:05:00"
      YAML

      expect(migrate).to be true

      data = read_yaml
      video = data['videos'].first
      expect(video).not_to have_key('transcript_path')
      expect(video['transcript']).to eq('DJI_0001.json')
    end

    it 'renames visual_transcript_path to visual_transcript with just the filename' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /Users/andrew/footage/DJI_0001.mov
            visual_transcript_path: "/Users/andrew/footage/transcripts/visual_DJI_0001.json"
            duration: "00:05:00"
      YAML

      expect(migrate).to be true

      video = read_yaml['videos'].first
      expect(video).not_to have_key('visual_transcript_path')
      expect(video['visual_transcript']).to eq('visual_DJI_0001.json')
    end

    it 'removes file_size_mb' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            file_size_mb: 256
            duration: "00:01:00"
      YAML

      expect(migrate).to be true
      expect(read_yaml['videos'].first).not_to have_key('file_size_mb')
    end

    it 'migrates all three fields in one pass' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/full/path/transcripts/clip.json"
            visual_transcript_path: "/full/path/transcripts/visual_clip.json"
            file_size_mb: 512
            duration: "00:10:00"
      YAML

      expect(migrate).to be true

      video = read_yaml['videos'].first
      expect(video['transcript']).to eq('clip.json')
      expect(video['visual_transcript']).to eq('visual_clip.json')
      expect(video).not_to have_key('transcript_path')
      expect(video).not_to have_key('visual_transcript_path')
      expect(video).not_to have_key('file_size_mb')
    end

    it 'handles multiple videos, migrating each independently' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/a.mov
            transcript_path: "/full/path/transcripts/a.json"
            duration: "00:01:00"
          - path: /tmp/b.mov
            visual_transcript_path: "/full/path/transcripts/visual_b.json"
            file_size_mb: 100
            duration: "00:02:00"
          - path: /tmp/c.mov
            duration: "00:03:00"
      YAML

      expect(migrate).to be true

      videos = read_yaml['videos']
      expect(videos[0]['transcript']).to eq('a.json')
      expect(videos[0]).not_to have_key('transcript_path')
      expect(videos[1]['visual_transcript']).to eq('visual_b.json')
      expect(videos[1]).not_to have_key('file_size_mb')
      expect(videos[2].keys).to contain_exactly('path', 'duration')
    end

    it 'is idempotent — no changes on a second run' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/full/path/transcripts/clip.json"
            duration: "00:01:00"
      YAML

      migrate
      first_pass = read_raw
      expect(migrate).to be false
      expect(read_raw).to eq(first_pass)
    end

    it 'returns false when there are no videos' do
      write_yaml(<<~YAML)
        library_name: test-lib
      YAML

      expect(migrate).to be false
    end

    it 'returns false when videos is an empty array' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos: []
      YAML

      expect(migrate).to be false
    end

    it 'returns false for a missing file' do
      expect(migrate_library('/nonexistent/library.yaml')).to be false
    end

    it 'handles non-ASCII content in other fields' do
      write_yaml(<<~YAML)
        library_name: test-lib
        footage_summary: "Café scenes — shots of the château's entrée"
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/full/path/transcripts/clip.json"
            duration: "00:01:00"
      YAML

      expect(migrate).to be true
      data = read_yaml
      expect(data['footage_summary']).to include('Café')
      expect(data['footage_summary']).to include('château')
      expect(data['videos'].first['transcript']).to eq('clip.json')
    end

    it 'preserves other video fields untouched' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/full/path/transcripts/clip.json"
            duration: "00:10:32"
            contact_sheet: "clip_full.jpg"
      YAML

      migrate
      video = read_yaml['videos'].first
      expect(video['path']).to eq('/tmp/clip.mov')
      expect(video['duration']).to eq('00:10:32')
      expect(video['contact_sheet']).to eq('clip_full.jpg')
    end

    it 'preserves top-level metadata fields' do
      write_yaml(<<~YAML)
        library_name: test-lib
        created_date: 2025-12-01
        language: english
        user_context: "The tall guy is Andrew"
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/full/path/transcripts/clip.json"
            duration: "00:01:00"
      YAML

      migrate
      data = read_yaml
      expect(data['library_name']).to eq('test-lib')
      expect(data['created_date']).to eq(Date.new(2025, 12, 1))
      expect(data['language']).to eq('english')
      expect(data['user_context']).to eq('The tall guy is Andrew')
    end

    it 'extracts only the basename from deeply nested paths' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript_path: "/Users/andrew/code/buttercut/libraries/my-lib/transcripts/DJI_20250423_0210.json"
            duration: "00:01:00"
      YAML

      migrate
      expect(read_yaml['videos'].first['transcript']).to eq('DJI_20250423_0210.json')
    end
  end

  # ─── 002: add transcript_refinement ───

  describe '002_migrate_add_transcript_refinement' do
    before(:context) { load File.expand_path('../scripts/002_migrate_add_transcript_refinement.rb', __dir__) }

    def migrate(name = 'test-lib')
      migrate_library(library_yaml_path(name))
    end

    it 'inserts transcript_refinement: false after the language: line' do
      write_yaml(<<~YAML)
        library_name: test-lib
        created_date: 2025-10-01
        language: english
        user_context: ""
        videos: []
      YAML

      expect(migrate).to be true

      data = read_yaml
      expect(data['transcript_refinement']).to be false
    end

    it 'places the new key on the line immediately after language:' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        user_context: ""
        videos: []
      YAML

      migrate
      lines = read_raw.lines.map(&:strip)
      lang_idx = lines.index('language: english')
      expect(lines[lang_idx + 1]).to eq('transcript_refinement: false')
    end

    it 'defaults to false, not true (pre-existing libraries never had refinement)' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        videos: []
      YAML

      migrate
      expect(read_yaml['transcript_refinement']).to be false
    end

    it 'is idempotent — skips when transcript_refinement already exists as false' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        transcript_refinement: false
        videos: []
      YAML

      expect(migrate).to be false
      expect(read_yaml['transcript_refinement']).to be false
    end

    it 'skips when transcript_refinement already exists as true' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        transcript_refinement: true
        videos: []
      YAML

      expect(migrate).to be false
      expect(read_yaml['transcript_refinement']).to be true
    end

    it 'returns false when there is no language: key' do
      write_yaml(<<~YAML)
        library_name: test-lib
        user_context: ""
        videos: []
      YAML

      expect(migrate).to be false
      expect(read_yaml).not_to have_key('transcript_refinement')
    end

    it 'returns false for a missing file' do
      expect(migrate_library('/nonexistent/library.yaml')).to be false
    end

    it 'preserves quote styles and formatting (textual edit, not YAML round-trip)' do
      content = <<~YAML
        library_name: test-lib
        language: english
        user_context: "The tall guy is Andrew"
        footage_summary: "Café scenes — shots of the château"
        videos: []
      YAML
      write_yaml(content)
      migrate

      raw = read_raw
      expect(raw).to include('"The tall guy is Andrew"')
      expect(raw).to include('"Café scenes — shots of the château"')
    end

    it 'handles non-ASCII content without crashing' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        footage_summary: "Em-dash — and accented café château"
        videos: []
      YAML

      expect { migrate }.not_to raise_error
      expect(read_yaml['transcript_refinement']).to be false
    end

    it 'produces valid YAML after insertion' do
      write_yaml(<<~YAML)
        library_name: test-lib
        created_date: 2025-10-01
        last_updated: 2025-11-15
        language: english
        user_context: "context"
        footage_summary: "summary"
        videos:
          - path: /tmp/a.mov
            duration: "00:05:00"
            transcript: a.json
      YAML

      migrate
      data = read_yaml
      expect(data).to be_a(Hash)
      expect(data['transcript_refinement']).to be false
      expect(data['videos']).to be_an(Array)
      expect(data['videos'].first['path']).to eq('/tmp/a.mov')
    end
  end

  # ─── 003: add summary to video entries ───

  describe '003_migrate_add_summary' do
    before(:context) { load File.expand_path('../scripts/003_migrate_add_summary.rb', __dir__) }

    def migrate(name = 'test-lib')
      migrate_library(library_yaml_path(name))
    end

    it 'inserts summary: after visual_transcript: in a video entry' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
      YAML

      expect(migrate).to be true

      data = read_yaml
      expect(data['videos'].first).to have_key('summary')
      expect(data['videos'].first['summary']).to be_nil
    end

    it 'places summary: on the line immediately after visual_transcript:' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
      YAML

      migrate
      lines = read_raw.lines
      vt_line = lines.index { |l| l.include?('visual_transcript:') }
      expect(lines[vt_line + 1].strip).to eq('summary:')
    end

    it 'preserves the indentation of the visual_transcript: line' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
      YAML

      migrate
      lines = read_raw.lines
      vt_line = lines.find { |l| l.include?('visual_transcript:') }
      summary_line = lines.find { |l| l.include?('summary:') }
      vt_indent = vt_line[/^\s*/]
      summary_indent = summary_line[/^\s*/]
      expect(summary_indent).to eq(vt_indent)
    end

    it 'handles multiple videos, inserting summary: after each visual_transcript:' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/a.mov
            transcript: a.json
            visual_transcript: visual_a.json
          - path: /tmp/b.mov
            transcript: b.json
            visual_transcript: visual_b.json
          - path: /tmp/c.mov
            transcript: c.json
            visual_transcript: visual_c.json
      YAML

      expect(migrate).to be true

      data = read_yaml
      data['videos'].each do |video|
        expect(video).to have_key('summary')
      end
    end

    it 'skips videos without visual_transcript: (mid-pipeline)' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/a.mov
            transcript: a.json
            visual_transcript: visual_a.json
          - path: /tmp/b.mov
            transcript: ""
      YAML

      migrate
      data = read_yaml
      expect(data['videos'][0]).to have_key('summary')
      expect(data['videos'][1]).not_to have_key('summary')
    end

    it 'is idempotent — skips entries that already have summary:' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
            summary: summary_clip.md
      YAML

      expect(migrate).to be false
    end

    it 'handles a mix of migrated and unmigrated entries' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/a.mov
            transcript: a.json
            visual_transcript: visual_a.json
            summary: summary_a.md
          - path: /tmp/b.mov
            transcript: b.json
            visual_transcript: visual_b.json
      YAML

      expect(migrate).to be true

      data = read_yaml
      expect(data['videos'][0]['summary']).to eq('summary_a.md')
      expect(data['videos'][1]).to have_key('summary')
    end

    it 'returns false when there are no visual_transcript: lines at all' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            contact_sheet: clip_full.jpg
            summary: summary_clip.md
      YAML

      expect(migrate).to be false
    end

    it 'returns false for a missing file' do
      expect(migrate_library('/nonexistent/library.yaml')).to be false
    end

    it 'produces valid YAML after insertion' do
      write_yaml(<<~YAML)
        library_name: test-lib
        language: english
        videos:
          - path: /tmp/a.mov
            transcript: a.json
            visual_transcript: visual_a.json
          - path: /tmp/b.mov
            transcript: b.json
            visual_transcript: visual_b.json
      YAML

      migrate
      data = read_yaml
      expect(data).to be_a(Hash)
      expect(data['videos']).to be_an(Array)
      expect(data['videos'].size).to eq(2)
    end

    it 'handles non-ASCII content without crashing' do
      write_yaml(<<~YAML)
        library_name: test-lib
        footage_summary: "Café — château entrée"
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
      YAML

      expect { migrate }.not_to raise_error
      expect(read_yaml['videos'].first).to have_key('summary')
    end

    it 'preserves formatting elsewhere in the file (textual edit, not YAML round-trip)' do
      content = <<~YAML
        library_name: test-lib
        user_context: "The tall guy is Andrew"
        videos:
          - path: /tmp/clip.mov
            transcript: clip.json
            visual_transcript: visual_clip.json
      YAML
      write_yaml(content)
      migrate

      raw = read_raw
      expect(raw).to include('"The tall guy is Andrew"')
    end
  end

  # ─── 004: roughcuts/ → cuts/ ───

  describe '004_migrate_roughcuts_to_cuts' do
    before(:context) { load File.expand_path('../scripts/004_migrate_roughcuts_to_cuts.rb', __dir__) }

    def migrate(name = 'test-lib')
      migrate_library(library_dir(name))
    end

    def setup_library(name = 'test-lib')
      FileUtils.mkdir_p(library_dir(name))
    end

    it 'renames roughcuts/ to cuts/ when only roughcuts/ exists' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      FileUtils.mkdir_p(roughcuts)
      File.write(File.join(roughcuts, 'scene_01.xml'), '<xml/>')

      expect(migrate).to be true
      expect(File.directory?(File.join(library_dir, 'cuts'))).to be true
      expect(File.directory?(roughcuts)).to be false
      expect(File.read(File.join(library_dir, 'cuts', 'scene_01.xml'))).to eq('<xml/>')
    end

    it 'skips when only cuts/ exists (already migrated)' do
      setup_library
      FileUtils.mkdir_p(File.join(library_dir, 'cuts'))

      expect(migrate).to be false
    end

    it 'skips when neither directory exists' do
      setup_library

      expect(migrate).to be false
    end

    it 'merges roughcuts/ into cuts/ when both exist without conflicts' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      cuts = File.join(library_dir, 'cuts')
      FileUtils.mkdir_p(roughcuts)
      FileUtils.mkdir_p(cuts)

      File.write(File.join(roughcuts, 'old_scene.xml'), '<old/>')
      File.write(File.join(cuts, 'new_scene.xml'), '<new/>')

      expect(migrate).to be true

      expect(File.exist?(File.join(cuts, 'old_scene.xml'))).to be true
      expect(File.exist?(File.join(cuts, 'new_scene.xml'))).to be true
      expect(File.read(File.join(cuts, 'old_scene.xml'))).to eq('<old/>')
      expect(File.directory?(roughcuts)).to be false
    end

    it 'refuses to merge when there are filename conflicts' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      cuts = File.join(library_dir, 'cuts')
      FileUtils.mkdir_p(roughcuts)
      FileUtils.mkdir_p(cuts)

      File.write(File.join(roughcuts, 'scene.xml'), '<roughcut version/>')
      File.write(File.join(cuts, 'scene.xml'), '<cuts version/>')

      expect(migrate).to be false

      expect(File.read(File.join(roughcuts, 'scene.xml'))).to eq('<roughcut version/>')
      expect(File.read(File.join(cuts, 'scene.xml'))).to eq('<cuts version/>')
    end

    it 'preserves all file contents during rename' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      FileUtils.mkdir_p(roughcuts)

      3.times do |i|
        File.write(File.join(roughcuts, "cut_#{i}.xml"), "<timeline>#{i}</timeline>")
      end

      migrate

      3.times do |i|
        expect(File.read(File.join(library_dir, 'cuts', "cut_#{i}.xml"))).to eq("<timeline>#{i}</timeline>")
      end
    end

    it 'handles an empty roughcuts/ directory' do
      setup_library
      FileUtils.mkdir_p(File.join(library_dir, 'roughcuts'))

      expect(migrate).to be true
      expect(File.directory?(File.join(library_dir, 'cuts'))).to be true
      expect(File.directory?(File.join(library_dir, 'roughcuts'))).to be false
    end

    it 'merges multiple files from roughcuts/ into existing cuts/' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      cuts = File.join(library_dir, 'cuts')
      FileUtils.mkdir_p(roughcuts)
      FileUtils.mkdir_p(cuts)

      File.write(File.join(roughcuts, 'a.xml'), 'a')
      File.write(File.join(roughcuts, 'b.xml'), 'b')
      File.write(File.join(cuts, 'c.xml'), 'c')

      expect(migrate).to be true

      expect(Dir.children(cuts).sort).to eq(%w[a.xml b.xml c.xml])
      expect(File.directory?(roughcuts)).to be false
    end

    it 'returns false for a nonexistent library directory' do
      expect(migrate_library('/nonexistent/library')).to be false
    end

    it 'detects multiple conflicts and leaves both directories intact' do
      setup_library
      roughcuts = File.join(library_dir, 'roughcuts')
      cuts = File.join(library_dir, 'cuts')
      FileUtils.mkdir_p(roughcuts)
      FileUtils.mkdir_p(cuts)

      File.write(File.join(roughcuts, 'x.xml'), '1')
      File.write(File.join(roughcuts, 'y.xml'), '2')
      File.write(File.join(cuts, 'x.xml'), '3')
      File.write(File.join(cuts, 'y.xml'), '4')

      expect(migrate).to be false

      expect(File.read(File.join(roughcuts, 'x.xml'))).to eq('1')
      expect(File.read(File.join(cuts, 'y.xml'))).to eq('4')
    end
  end

  # ─── 005: rename top-level videos: → media: ───

  describe '005_migrate_videos_to_media' do
    before(:context) { load File.expand_path('../scripts/005_migrate_videos_to_media.rb', __dir__) }

    def migrate(name = 'test-lib')
      migrate_library(library_yaml_path(name))
    end

    it 'renames the top-level videos: key to media:' do
      write_yaml(<<~YAML)
        library_name: test-lib
        videos:
          - path: /tmp/DJI_0001.mov
            duration: "00:05:00"
            transcript: ""
            contact_sheet: ""
            summary: ""
      YAML

      expect(migrate).to be true
      data = read_yaml
      expect(data).to have_key('media')
      expect(data).not_to have_key('videos')
      expect(data['media'].first['path']).to eq('/tmp/DJI_0001.mov')
    end

    it 'preserves quote styles and indentation elsewhere — only the key line changes' do
      original = <<~YAML
        library_name: test-lib
        footage_summary: "Wedding footage from São Paulo"
        videos:
          - path: /tmp/a.mov
            duration: "00:05:00"
      YAML
      write_yaml(original)
      migrate
      expect(read_raw).to eq(original.sub(/^videos:/, 'media:'))
    end

    it 'is a no-op when already on media: (idempotent)' do
      write_yaml(<<~YAML)
        library_name: test-lib
        media:
          - path: /tmp/a.mov
            summary: ""
      YAML
      expect(migrate).to be false
      expect(read_yaml).to have_key('media')
    end

    it 'is a no-op when there is no videos: key at all' do
      write_yaml(<<~YAML)
        library_name: test-lib
        media: []
      YAML
      expect(migrate).to be false
    end

    it 'returns false for a nonexistent library file' do
      expect(migrate_library('/nonexistent/library.yaml')).to be false
    end
  end

  # ─── migrate_all.rb orchestrator ───

  describe 'migrate_all' do
    let(:script_path) { File.expand_path('../scripts/migrate_all.rb', __dir__) }
    let(:repo_root) { File.expand_path('..', __dir__) }

    it 'runs all numbered migration scripts in order' do
      Dir.chdir(repo_root) do
        output = `ruby #{script_path} 2>&1`
        expect($?.success?).to be(true), "migrate_all.rb failed:\n#{output}"
        expect(output).to include('001_migrate_0.2_to_0.3.rb')
        expect(output).to include('002_migrate_add_transcript_refinement.rb')
        expect(output).to include('003_migrate_add_summary.rb')
        expect(output).to include('004_migrate_roughcuts_to_cuts.rb')
        expect(output).to include('005_migrate_videos_to_media.rb')
      end
    end

    it 'runs scripts in numeric order' do
      Dir.chdir(repo_root) do
        output = `ruby #{script_path} 2>&1`
        positions = %w[001 002 003 004 005].map { |n| output.index(n) }
        expect(positions).to eq(positions.sort)
      end
    end

    it 'succeeds even with no libraries present' do
      Dir.mktmpdir('empty-repo-') do |tmpdir|
        FileUtils.mkdir_p(File.join(tmpdir, 'scripts'))
        FileUtils.mkdir_p(File.join(tmpdir, 'libraries'))

        # Copy migration scripts to the temp directory
        Dir.glob(File.join(repo_root, 'scripts', '[0-9]*_migrate_*.rb')).each do |script|
          FileUtils.cp(script, File.join(tmpdir, 'scripts'))
        end
        FileUtils.cp(File.join(repo_root, 'scripts', 'migrate_all.rb'), File.join(tmpdir, 'scripts'))

        Dir.chdir(tmpdir) do
          output = `ruby scripts/migrate_all.rb 2>&1`
          expect($?.success?).to be(true), "migrate_all.rb failed with no libraries:\n#{output}"
        end
      end
    end
  end

  # ─── Full pipeline: all migrations run in sequence on a v0.2 library ───

  describe 'full migration pipeline (v0.2 → current)' do
    it 'migrates a v0.2 library through all scripts to the current schema' do
      v02_yaml = <<~YAML
        library_name: legacy-project
        created_date: 2025-08-15
        last_updated: 2025-09-01
        language: english
        user_context: "The woman in red is Maria"
        footage_description: "Wedding footage from São Paulo"
        videos:
          - path: /Volumes/SSD/wedding/DJI_0001.mov
            transcript_path: "/Volumes/SSD/wedding/transcripts/DJI_0001.json"
            visual_transcript_path: "/Volumes/SSD/wedding/transcripts/visual_DJI_0001.json"
            file_size_mb: 1024
            duration: "00:15:32"
          - path: /Volumes/SSD/wedding/DJI_0002.mov
            transcript_path: "/Volumes/SSD/wedding/transcripts/DJI_0002.json"
            file_size_mb: 768
            duration: "00:08:45"
          - path: /Volumes/SSD/wedding/DJI_0003.mov
            duration: "00:03:20"
      YAML

      write_yaml(v02_yaml)
      FileUtils.mkdir_p(File.join(library_dir, 'roughcuts'))
      File.write(File.join(library_dir, 'roughcuts', 'first_draft.xml'), '<timeline/>')

      # Run 001: transcript_path → transcript, remove file_size_mb
      load File.expand_path('../scripts/001_migrate_0.2_to_0.3.rb', __dir__)
      expect(migrate_library(library_yaml_path)).to be true

      data = read_yaml
      expect(data['videos'][0]['transcript']).to eq('DJI_0001.json')
      expect(data['videos'][0]['visual_transcript']).to eq('visual_DJI_0001.json')
      expect(data['videos'][0]).not_to have_key('transcript_path')
      expect(data['videos'][0]).not_to have_key('file_size_mb')
      expect(data['videos'][1]['transcript']).to eq('DJI_0002.json')
      expect(data['videos'][1]).not_to have_key('file_size_mb')

      # Run 002: add transcript_refinement
      load File.expand_path('../scripts/002_migrate_add_transcript_refinement.rb', __dir__)
      expect(migrate_library(library_yaml_path)).to be true
      expect(read_yaml['transcript_refinement']).to be false

      # Run 003: add summary to video entries with visual_transcript
      load File.expand_path('../scripts/003_migrate_add_summary.rb', __dir__)
      expect(migrate_library(library_yaml_path)).to be true

      data = read_yaml
      expect(data['videos'][0]).to have_key('summary')
      expect(data['videos'][2]).not_to have_key('summary')

      # Run 004: roughcuts/ → cuts/
      load File.expand_path('../scripts/004_migrate_roughcuts_to_cuts.rb', __dir__)
      expect(migrate_library(library_dir)).to be true
      expect(File.directory?(File.join(library_dir, 'cuts'))).to be true
      expect(File.directory?(File.join(library_dir, 'roughcuts'))).to be false
      expect(File.read(File.join(library_dir, 'cuts', 'first_draft.xml'))).to eq('<timeline/>')

      # Run 005: videos: → media:
      load File.expand_path('../scripts/005_migrate_videos_to_media.rb', __dir__)
      expect(migrate_library(library_yaml_path)).to be true

      # Verify final state — now on the current media: schema
      final = read_yaml
      expect(final['library_name']).to eq('legacy-project')
      expect(final['language']).to eq('english')
      expect(final['transcript_refinement']).to be false
      expect(final['user_context']).to eq('The woman in red is Maria')
      expect(final).not_to have_key('videos')

      # All three clips still present with correct data, under media:
      expect(final['media'].size).to eq(3)
      expect(final['media'].map { |v| v['path'] }).to eq([
        '/Volumes/SSD/wedding/DJI_0001.mov',
        '/Volumes/SSD/wedding/DJI_0002.mov',
        '/Volumes/SSD/wedding/DJI_0003.mov'
      ])

      # Verify the full pipeline is idempotent
      snapshot = read_raw
      load File.expand_path('../scripts/001_migrate_0.2_to_0.3.rb', __dir__)
      migrate_library(library_yaml_path)
      load File.expand_path('../scripts/002_migrate_add_transcript_refinement.rb', __dir__)
      migrate_library(library_yaml_path)
      load File.expand_path('../scripts/003_migrate_add_summary.rb', __dir__)
      migrate_library(library_yaml_path)
      load File.expand_path('../scripts/004_migrate_roughcuts_to_cuts.rb', __dir__)
      migrate_library(library_dir)
      load File.expand_path('../scripts/005_migrate_videos_to_media.rb', __dir__)
      migrate_library(library_yaml_path)
      expect(read_raw).to eq(snapshot)
    end

    it 'handles a library with only some legacy fields (partial v0.2)' do
      write_yaml(<<~YAML)
        library_name: partial
        language: english
        videos:
          - path: /tmp/a.mov
            transcript_path: "/full/path/a.json"
            duration: "00:05:00"
          - path: /tmp/b.mov
            transcript: b.json
            visual_transcript: visual_b.json
            summary: summary_b.md
            duration: "00:03:00"
      YAML

      load File.expand_path('../scripts/001_migrate_0.2_to_0.3.rb', __dir__)
      migrate_library(library_yaml_path)

      load File.expand_path('../scripts/002_migrate_add_transcript_refinement.rb', __dir__)
      migrate_library(library_yaml_path)

      load File.expand_path('../scripts/003_migrate_add_summary.rb', __dir__)
      migrate_library(library_yaml_path)

      data = read_yaml
      expect(data['videos'][0]['transcript']).to eq('a.json')
      expect(data['videos'][0]).not_to have_key('transcript_path')
      expect(data['videos'][1]['summary']).to eq('summary_b.md')
      expect(data['transcript_refinement']).to be false
    end
  end
end
