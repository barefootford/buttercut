require 'spec_helper'
require 'tmpdir'
require 'yaml'
require_relative '../skills/buttercut-lib/library'

RSpec.describe Library do
  let(:libraries_root) { @libraries_root }
  let(:library_name) { 'test-lib' }
  let(:library_dir) { File.join(libraries_root, library_name) }
  let(:library_yaml_path) { File.join(library_dir, 'library.yaml') }

  around do |example|
    Dir.mktmpdir('library-spec-') do |root|
      @libraries_root = root
      example.run
    end
  end

  before do
    stub_const('Library::LIBRARIES_ROOT', @libraries_root)
    allow($stdout).to receive(:puts)
  end

  def write_library(videos:, name: library_name, **metadata)
    dir = File.join(libraries_root, name)
    FileUtils.mkdir_p(File.join(dir, 'transcripts'))
    FileUtils.mkdir_p(File.join(dir, 'contact_sheets'))
    FileUtils.mkdir_p(File.join(dir, 'scripts'))
    FileUtils.mkdir_p(File.join(dir, 'summaries'))
    payload = metadata.transform_keys(&:to_s).merge('videos' => videos)
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    dir
  end

  def video_entry(filename, **overrides)
    {
      'path' => "/tmp/#{filename}",
      'duration' => '00:00:05',
      'transcript' => '',
      'contact_sheet' => '',
      'script' => '',
      'summary' => ''
    }.merge(overrides.transform_keys(&:to_s))
  end

  def touch(*paths)
    paths.each { |p| FileUtils.touch(p) }
  end

  def load_yaml
    YAML.safe_load_file(library_yaml_path)
  end

  describe '.exists?' do
    it 'returns true when both directory and library.yaml exist' do
      write_library(videos: [])
      expect(Library.exists?(library_name)).to be(true)
    end

    it 'returns false when the directory is missing' do
      expect(Library.exists?('nope')).to be(false)
    end

    it 'returns false when library.yaml is missing' do
      FileUtils.mkdir_p(library_dir)
      expect(Library.exists?(library_name)).to be(false)
    end

    it 'returns false for blank names' do
      expect(Library.exists?('')).to be(false)
      expect(Library.exists?(nil)).to be(false)
    end
  end

  describe '.list' do
    it 'returns library names sorted by library.yaml mtime (newest first)' do
      write_library(videos: [], name: 'older')
      write_library(videos: [], name: 'newer')
      File.utime(Time.now - 100, Time.now - 100, File.join(libraries_root, 'older', 'library.yaml'))
      File.utime(Time.now, Time.now, File.join(libraries_root, 'newer', 'library.yaml'))
      expect(Library.list).to eq(%w[newer older])
    end

    it 'ignores directories without a library.yaml' do
      write_library(videos: [], name: 'real')
      FileUtils.mkdir_p(File.join(libraries_root, 'half-built'))
      expect(Library.list).to eq(['real'])
    end

    it 'returns an empty array when the root is empty' do
      expect(Library.list).to eq([])
    end
  end

  describe '.create' do
    let(:video_path) { File.join(@libraries_root, 'src', 'a.mov') }

    before do
      FileUtils.mkdir_p(File.dirname(video_path))
      FileUtils.touch(video_path)
      allow(Library).to receive(:probe_duration).and_return('00:00:42')
    end

    it 'creates the directory tree, library.yaml, and returns a handle' do
      lib = Library.create(
        'fresh', language: 'en', editor: 'Final Cut Pro X',
        transcript_refinement: true, video_paths: [video_path]
      )
      expect(lib).to be_a(Library)
      expect(File.directory?(File.join(libraries_root, 'fresh', 'transcripts'))).to be(true)
      expect(File.directory?(File.join(libraries_root, 'fresh', 'roughcuts'))).to be(true)

      yaml = YAML.safe_load_file(File.join(libraries_root, 'fresh', 'library.yaml'), permitted_classes: [Date, Time])
      expect(yaml).to include(
        'library_name' => 'fresh', 'language' => 'en', 'editor' => 'Final Cut Pro X',
        'transcript_refinement' => true, 'user_context' => ''
      )
      expect(yaml['videos'].first).to include(
        'path' => video_path, 'duration' => '00:00:42',
        'transcript' => '', 'script' => '', 'contact_sheet' => '', 'summary' => ''
      )
    end

    it 'refuses to overwrite an existing library' do
      write_library(videos: [], name: 'fresh')
      expect do
        Library.create('fresh', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, video_paths: [video_path])
      end.to raise_error(ArgumentError, /already exists/)
    end

    it 'raises when a video file is missing' do
      expect do
        Library.create('fresh', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, video_paths: ['/nope.mov'])
      end.to raise_error(ArgumentError, /video file not found/)
    end

    it 'rejects a blank library name' do
      expect do
        Library.create('', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, video_paths: [])
      end.to raise_error(ArgumentError, /library_name is required/)
    end
  end

  describe '#add_videos' do
    let(:video_a) { File.join(@libraries_root, 'src', 'a.mov') }
    let(:video_b) { File.join(@libraries_root, 'src', 'b.mov') }

    before do
      FileUtils.mkdir_p(File.dirname(video_a))
      FileUtils.touch(video_a)
      FileUtils.touch(video_b)
      allow(Library).to receive(:probe_duration).and_return('00:00:10')
      write_library(videos: [video_entry('existing.mov', path: '/tmp/existing.mov')])
    end

    it 'appends new entries with ffprobe duration and empty per-clip fields' do
      Library.find(library_name).add_videos([video_a, video_b])
      videos = load_yaml['videos']
      expect(videos.map { |v| v['path'] }).to eq(['/tmp/existing.mov', video_a, video_b])
      expect(videos.last).to include('duration' => '00:00:10', 'transcript' => '', 'summary' => '')
    end

    it 'refuses to add a path already in the library' do
      Library.find(library_name).add_videos([video_a])
      expect { Library.find(library_name).add_videos([video_a]) }
        .to raise_error(ArgumentError, /already in library/)
    end

    it 'raises if the video file does not exist on disk' do
      expect { Library.find(library_name).add_videos(['/nope.mov']) }
        .to raise_error(ArgumentError, /video file not found/)
    end

    it 'coerces a single path into a one-element array' do
      Library.find(library_name).add_videos(video_a)
      expect(load_yaml['videos'].last['path']).to eq(video_a)
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.add_videos([video_a])).to be(lib)
    end
  end

  describe '.find' do
    it 'returns a Library instance for an existing library' do
      write_library(videos: [])
      expect(Library.find(library_name)).to be_a(Library)
    end

    it 'raises when the library directory is missing' do
      expect { Library.find('does-not-exist') }
        .to raise_error(ArgumentError, /library not found/)
    end

    it 'raises when library.yaml is missing' do
      FileUtils.mkdir_p(library_dir)
      expect { Library.find(library_name) }
        .to raise_error(ArgumentError, /library\.yaml not found/)
    end

    it 'raises on a blank library name' do
      expect { Library.find('') }.to raise_error(ArgumentError, /library_name is required/)
      expect { Library.find(nil) }.to raise_error(ArgumentError, /library_name is required/)
    end
  end

  describe '#summary' do
    it 'returns top-level metadata plus a clip-completion breakdown' do
      write_library(
        videos: [
          video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg',
                      script: 'script_a.txt', summary: 'summary_a.md'),
          video_entry('b.mov', transcript: 'b.json', summary: 'summary_b.md'),
          video_entry('c.mov')
        ],
        created_date: '2026-01-15',
        last_updated: '2026-05-18',
        language: 'en',
        editor: 'Final Cut Pro X',
        transcript_refinement: true,
        user_context: 'user is Andrew',
        footage_summary: 'cycling in Lisbon'
      )

      result = Library.find(library_name).summary
      expect(result).to include(
        'name' => library_name,
        'created_date' => '2026-01-15',
        'last_updated' => '2026-05-18',
        'language' => 'en',
        'editor' => 'Final Cut Pro X',
        'transcript_refinement' => true,
        'user_context' => 'user is Andrew',
        'footage_summary' => 'cycling in Lisbon',
        'video_count' => 3,
        'complete_count' => 1,
        'incomplete_count' => 2
      )
      expect(result['incomplete'].map { |v| v['filename'] }).to eq(%w[b.mov c.mov])
      expect(result['incomplete'].first['missing']).to eq(%w[contact_sheet script])
    end

    it 'returns zero counts and an empty incomplete list for a brand-new empty library' do
      write_library(videos: [], footage_summary: 'No footage analyzed yet.')
      result = Library.find(library_name).summary
      expect(result).to include('video_count' => 0, 'complete_count' => 0, 'incomplete_count' => 0, 'incomplete' => [])
    end

    it 'defaults free-text fields to empty strings when absent' do
      write_library(videos: [])
      result = Library.find(library_name).summary
      expect(result['user_context']).to eq('')
      expect(result['footage_summary']).to eq('')
    end
  end

  describe '#dir' do
    it 'returns the absolute path to the library directory' do
      write_library(videos: [])
      expect(Library.find(library_name).dir).to eq(library_dir)
    end
  end

  describe '#field_path' do
    before { write_library(videos: []) }

    it 'returns the canonical on-disk path for each field' do
      lib = Library.find(library_name)
      expect(lib.field_path('transcript', 'DJI_0123')).to eq(File.join(library_dir, 'transcripts', 'DJI_0123.json'))
      expect(lib.field_path('contact_sheet', 'DJI_0123')).to eq(File.join(library_dir, 'contact_sheets', 'DJI_0123_full.jpg'))
      expect(lib.field_path('script', 'DJI_0123')).to eq(File.join(library_dir, 'scripts', 'script_DJI_0123.txt'))
      expect(lib.field_path('summary', 'DJI_0123')).to eq(File.join(library_dir, 'summaries', 'summary_DJI_0123.md'))
    end

    it 'raises for unknown fields' do
      expect { Library.find(library_name).field_path('bogus', 'x') }
        .to raise_error(ArgumentError, /unknown field/)
    end
  end

  describe '#videos' do
    it 'returns the video entries from library.yaml' do
      write_library(videos: [video_entry('a.mov'), video_entry('b.mov')])
      videos = Library.find(library_name).videos
      expect(videos.map { |v| v['path'] }).to eq(['/tmp/a.mov', '/tmp/b.mov'])
    end

    it 'returns an empty array when there are no videos' do
      write_library(videos: [])
      expect(Library.find(library_name).videos).to eq([])
    end
  end

  describe 'metadata readers' do
    it 'returns top-level fields from library.yaml' do
      write_library(
        videos: [],
        language: 'en',
        transcript_refinement: true,
        user_context: 'user is Andrew',
        footage_summary: 'cycling in Lisbon',
        editor: 'Final Cut Pro X'
      )
      lib = Library.find(library_name)
      expect(lib.language).to eq('en')
      expect(lib.transcript_refinement).to be(true)
      expect(lib.user_context).to eq('user is Andrew')
      expect(lib.footage_summary).to eq('cycling in Lisbon')
      expect(lib.editor).to eq('Final Cut Pro X')
    end

    it 'returns sensible defaults when fields are absent' do
      write_library(videos: [])
      lib = Library.find(library_name)
      expect(lib.language).to be_nil
      expect(lib.transcript_refinement).to be_nil
      expect(lib.user_context).to eq('')
      expect(lib.footage_summary).to eq('')
      expect(lib.editor).to be_nil
    end
  end

  describe '#update_metadata!' do
    it 'updates footage_summary and user_context independently' do
      write_library(videos: [], footage_summary: 'old summary', user_context: 'old context')
      Library.find(library_name).update_metadata!(footage_summary: 'new summary')
      reloaded = load_yaml
      expect(reloaded['footage_summary']).to eq('new summary')
      expect(reloaded['user_context']).to eq('old context')
    end

    it 'leaves untouched fields alone' do
      write_library(videos: [], footage_summary: 'keep me', user_context: 'and me')
      Library.find(library_name).update_metadata!
      reloaded = load_yaml
      expect(reloaded['footage_summary']).to eq('keep me')
      expect(reloaded['user_context']).to eq('and me')
    end

    it 'accepts empty strings to clear a field' do
      write_library(videos: [], footage_summary: 'old')
      Library.find(library_name).update_metadata!(footage_summary: '')
      expect(load_yaml['footage_summary']).to eq('')
    end

    it 'returns self for chaining' do
      write_library(videos: [])
      lib = Library.find(library_name)
      expect(lib.update_metadata!(footage_summary: 'x')).to be(lib)
    end
  end

  describe '#incomplete_videos' do
    it 'returns an empty array when every video has all four fields set' do
      write_library(videos: [
                      video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg',
                                  script: 'script_a.txt', summary: 'summary_a.md')
                    ])
      expect(Library.find(library_name).incomplete_videos).to eq([])
    end

    it 'reports each missing field' do
      write_library(videos: [
                      video_entry('a.mov', transcript: 'a.json'),
                      video_entry('b.mov', transcript: 'b.json', summary: 'summary_b.md')
                    ])
      result = Library.find(library_name).incomplete_videos
      expect(result.size).to eq(2)
      expect(result[0]).to include('filename' => 'a.mov', 'missing' => %w[contact_sheet script summary])
      expect(result[1]).to include('filename' => 'b.mov', 'missing' => %w[contact_sheet script])
    end

    it 'treats nil and whitespace-only values as missing' do
      write_library(videos: [video_entry('a.mov', transcript: nil, script: '   ')])
      expect(Library.find(library_name).incomplete_videos.first['missing'])
        .to include('transcript', 'script')
    end

    it 'ignores legacy visual_transcript when reporting missing fields' do
      write_library(videos: [
                      video_entry('a.mov', summary: 'summary_a.md').merge('visual_transcript' => 'visual_a.json')
                    ])
      expect(Library.find(library_name).incomplete_videos.first['missing'])
        .to eq(%w[transcript contact_sheet script])
    end
  end

  describe '#processed?' do
    it 'returns true when every video has script + summary (current pipeline)' do
      write_library(videos: [
                      video_entry('a.mov', script: 'script_a.txt', summary: 'summary_a.md'),
                      video_entry('b.mov', script: 'script_b.txt', summary: 'summary_b.md')
                    ])
      expect(Library.find(library_name).processed?).to be(true)
    end

    it 'returns true when every video has visual_transcript + summary (legacy)' do
      write_library(videos: [
                      video_entry('a.mov', summary: 'summary_a.md').merge('visual_transcript' => 'visual_a.json')
                    ])
      expect(Library.find(library_name).processed?).to be(true)
    end

    it 'accepts a mix of legacy and current videos' do
      write_library(videos: [
                      video_entry('a.mov', script: 'script_a.txt', summary: 'summary_a.md'),
                      video_entry('b.mov', summary: 'summary_b.md').merge('visual_transcript' => 'visual_b.json')
                    ])
      expect(Library.find(library_name).processed?).to be(true)
    end

    it 'returns false when any video is missing a summary' do
      write_library(videos: [
                      video_entry('a.mov', script: 'script_a.txt', summary: 'summary_a.md'),
                      video_entry('b.mov', script: 'script_b.txt')
                    ])
      expect(Library.find(library_name).processed?).to be(false)
    end

    it 'returns false for an empty library' do
      write_library(videos: [])
      expect(Library.find(library_name).processed?).to be(false)
    end
  end

  describe '#complete!' do
    before do
      write_library(videos: [video_entry('a.mov'), video_entry('b.mov'), video_entry('c.mov')])
      touch(
        File.join(library_dir, 'summaries', 'summary_a.md'),
        File.join(library_dir, 'summaries', 'summary_b.md'),
        File.join(library_dir, 'summaries', 'summary_c.md')
      )
    end

    it 'sets the field on each named video' do
      Library.find(library_name).complete!('summary', ['a.mov', 'b.mov'])
      videos = load_yaml['videos']
      expect(videos[0]['summary']).to eq('summary_a.md')
      expect(videos[1]['summary']).to eq('summary_b.md')
      expect(videos[2]['summary']).to eq('')
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.complete!('summary', ['a.mov'])).to be(lib)
    end

    it 'raises if the file does not exist on disk and leaves YAML untouched' do
      File.delete(File.join(library_dir, 'summaries', 'summary_b.md'))
      expect { Library.find(library_name).complete!('summary', ['a.mov', 'b.mov']) }
        .to raise_error(ArgumentError, /summary file does not exist/)
      expect(load_yaml['videos'][0]['summary']).to eq('')
    end

    it 'raises if a video is not present in library.yaml' do
      touch(File.join(library_dir, 'summaries', 'summary_missing.md'))
      expect { Library.find(library_name).complete!('summary', ['missing.mov']) }
        .to raise_error(ArgumentError, /video not found in library\.yaml/)
    end

    it 'raises for an unknown field name' do
      expect { Library.find(library_name).complete!('bogus', ['a.mov']) }
        .to raise_error(ArgumentError, /unknown field/)
    end

    it 'coerces a single filename into a one-element batch' do
      Library.find(library_name).complete!('summary', 'a.mov')
      expect(load_yaml['videos'][0]['summary']).to eq('summary_a.md')
    end
  end

  describe '#reset!' do
    before do
      write_library(videos: [
                      video_entry('a.mov', summary: 'summary_a.md'),
                      video_entry('b.mov', summary: 'summary_b.md')
                    ])
      touch(
        File.join(library_dir, 'summaries', 'summary_a.md'),
        File.join(library_dir, 'summaries', 'summary_b.md')
      )
    end

    it 'deletes referenced files and clears YAML fields' do
      Library.find(library_name).reset!('summary')
      expect(Dir.children(File.join(library_dir, 'summaries'))).to eq([])
      expect(load_yaml['videos'].map { |v| v['summary'] }).to eq(['', ''])
    end

    it 'sweeps orphan files in the directory' do
      touch(File.join(library_dir, 'summaries', 'summary_orphan.md'))
      Library.find(library_name).reset!('summary')
      expect(Dir.children(File.join(library_dir, 'summaries'))).to eq([])
    end

    it 'is variadic — wipes every named field in one call' do
      write_library(videos: [
                      video_entry('a.mov', script: 'script_a.txt', summary: 'summary_a.md',
                                  contact_sheet: 'a_full.jpg')
                    ])
      touch(
        File.join(library_dir, 'scripts',        'script_a.txt'),
        File.join(library_dir, 'summaries',      'summary_a.md'),
        File.join(library_dir, 'contact_sheets', 'a_full.jpg')
      )
      Library.find(library_name).reset!('script', 'summary', 'contact_sheet')
      video = load_yaml['videos'].first
      expect(video.values_at('script', 'summary', 'contact_sheet')).to eq(['', '', ''])
      expect(Dir.children(File.join(library_dir, 'scripts'))).to eq([])
      expect(Dir.children(File.join(library_dir, 'summaries'))).to eq([])
      expect(Dir.children(File.join(library_dir, 'contact_sheets'))).to eq([])
    end

    it 'leaves legacy visual_*.json files alone when resetting transcripts' do
      write_library(videos: [video_entry('a.mov', transcript: 'a.json').merge('visual_transcript' => 'visual_a.json')])
      touch(
        File.join(library_dir, 'transcripts', 'a.json'),
        File.join(library_dir, 'transcripts', 'visual_a.json')
      )
      Library.find(library_name).reset!('transcript')
      expect(Dir.children(File.join(library_dir, 'transcripts'))).to eq(['visual_a.json'])
      expect(load_yaml['videos'].first['visual_transcript']).to eq('visual_a.json')
    end

    it 'raises for an unknown field name' do
      expect { Library.find(library_name).reset!('bogus') }
        .to raise_error(ArgumentError, /unknown field/)
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.reset!('summary')).to be(lib)
    end

    it 'rescues per-file errors so one bad entry does not abort the batch' do
      ref = File.join(library_dir, 'summaries', 'summary_a.md')
      allow(File).to receive(:delete).and_call_original
      allow(File).to receive(:delete).with(ref).and_raise(Errno::EACCES, 'denied')

      lib = Library.find(library_name)
      expect { lib.reset!('summary') }.not_to raise_error
      yaml = load_yaml['videos']
      expect(yaml[0]['summary']).to eq('summary_a.md') # not cleared — delete failed
      expect(yaml[1]['summary']).to eq('')             # cleared — delete succeeded
    end
  end

  describe '#remove_visual_transcripts!' do
    before do
      write_library(videos: [
                      video_entry('a.mov', transcript: 'a.json').merge('visual_transcript' => 'visual_a.json'),
                      video_entry('b.mov', transcript: 'b.json').merge('visual_transcript' => 'visual_b.json')
                    ])
      touch(
        File.join(library_dir, 'transcripts', 'a.json'),
        File.join(library_dir, 'transcripts', 'b.json'),
        File.join(library_dir, 'transcripts', 'visual_a.json'),
        File.join(library_dir, 'transcripts', 'visual_b.json')
      )
    end

    it 'deletes visual_*.json files in transcripts/ and clears the YAML field' do
      Library.find(library_name).remove_visual_transcripts!
      remaining = Dir.children(File.join(library_dir, 'transcripts')).sort
      expect(remaining).to eq(%w[a.json b.json])
      expect(load_yaml['videos'].map { |v| v['visual_transcript'] }).to eq(['', ''])
    end

    it 'leaves non-visual transcript files and other YAML fields intact' do
      Library.find(library_name).remove_visual_transcripts!
      yaml = load_yaml['videos']
      expect(yaml.map { |v| v['transcript'] }).to eq(%w[a.json b.json])
    end

    it 'is a no-op when no visual transcripts are present' do
      FileUtils.rm_rf(File.join(library_dir, 'transcripts'))
      FileUtils.mkdir_p(File.join(library_dir, 'transcripts'))
      write_library(videos: [video_entry('a.mov', transcript: 'a.json')])
      touch(File.join(library_dir, 'transcripts', 'a.json'))
      expect { Library.find(library_name).remove_visual_transcripts! }.not_to raise_error
      expect(Dir.children(File.join(library_dir, 'transcripts'))).to eq(['a.json'])
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.remove_visual_transcripts!).to be(lib)
    end
  end

end
