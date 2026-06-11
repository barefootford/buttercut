require 'spec_helper'
require 'tmpdir'
require 'yaml'
require_relative '../../lib/buttercut/library'

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

  def write_library(media:, name: library_name, **metadata)
    dir = File.join(libraries_root, name)
    FileUtils.mkdir_p(File.join(dir, 'transcripts'))
    FileUtils.mkdir_p(File.join(dir, 'contact_sheets'))
    FileUtils.mkdir_p(File.join(dir, 'summaries'))
    payload = metadata.transform_keys(&:to_s).merge('media' => media)
    File.write(File.join(dir, 'library.yaml'), payload.to_yaml)
    dir
  end

  # A video record: probed duration + the three video fields.
  def video_entry(filename, **overrides)
    {
      'path' => "/tmp/#{filename}",
      'duration' => '00:00:05',
      'transcript' => '',
      'contact_sheet' => '',
      'summary' => ''
    }.merge(overrides.transform_keys(&:to_s))
  end

  # An image record: no duration, no transcript/contact_sheet — just a summary.
  def image_entry(filename, **overrides)
    {
      'path' => "/tmp/#{filename}",
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
      write_library(media: [])
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
      write_library(media: [], name: 'older')
      write_library(media: [], name: 'newer')
      File.utime(Time.now - 100, Time.now - 100, File.join(libraries_root, 'older', 'library.yaml'))
      File.utime(Time.now, Time.now, File.join(libraries_root, 'newer', 'library.yaml'))
      expect(Library.list).to eq(%w[newer older])
    end

    it 'ignores directories without a library.yaml' do
      write_library(media: [], name: 'real')
      FileUtils.mkdir_p(File.join(libraries_root, 'half-built'))
      expect(Library.list).to eq(['real'])
    end

    it 'returns an empty array when the root is empty' do
      expect(Library.list).to eq([])
    end
  end

  describe '.recent' do
    it 'orders by the newest file mtime inside the library dir, not just library.yaml' do
      write_library(media: [], name: 'a')
      write_library(media: [], name: 'b')

      old = Time.now - 1000
      [%w[a library.yaml], %w[b library.yaml]].each { |parts| File.utime(old, old, File.join(libraries_root, *parts)) }

      transcript = File.join(libraries_root, 'b', 'transcripts', 'foo.json')
      File.write(transcript, '{}')

      expect(Library.recent).to eq(%w[b a])
    end

    it 'caps the result at limit (default 10)' do
      11.times { |i| write_library(media: [], name: "lib#{i}") }
      expect(Library.recent.size).to eq(10)
      expect(Library.recent(limit: 3).size).to eq(3)
    end

    it 'ignores directories without a library.yaml' do
      write_library(media: [], name: 'real')
      FileUtils.mkdir_p(File.join(libraries_root, 'half-built'))
      expect(Library.recent).to eq(['real'])
    end

    it 'returns an empty array when the root is empty' do
      expect(Library.recent).to eq([])
    end
  end

  describe '.media_type_of' do
    it 'infers video and image from the extension, case-insensitively' do
      expect(Library.media_type_of('/a/b/CLIP.MOV')).to eq('video')
      expect(Library.media_type_of('clip.mp4')).to eq('video')
      expect(Library.media_type_of('photo.JPEG')).to eq('image')
      expect(Library.media_type_of('x.png')).to eq('image')
    end

    it 'returns nil for an extension outside every set' do
      expect(Library.media_type_of('archive.mkv')).to be_nil
      expect(Library.media_type_of('clip.webm')).to be_nil
      expect(Library.media_type_of('noext')).to be_nil
    end
  end

  describe '.clip_key' do
    it 'strips the extension for videos so it matches artifacts already on disk' do
      expect(Library.clip_key('P1055017.mov')).to eq('P1055017')
    end

    it 'flattens the extension into the key for images so photo/video basenames cannot collide' do
      expect(Library.clip_key('DJI_0123.jpg')).to eq('DJI_0123_jpg')
      expect(Library.clip_key('DJI_0123.PNG')).to eq('DJI_0123_png')
    end
  end

  describe '.fields_for' do
    it 'returns the registry fields for each type' do
      expect(Library.fields_for('video')).to eq(%w[transcript contact_sheet summary])
      expect(Library.fields_for('image')).to eq(%w[summary])
    end

    it 'raises for an unknown type' do
      expect { Library.fields_for('audio') }.to raise_error(ArgumentError, /unknown media type/)
    end
  end

  describe '.create' do
    let(:video_path) { File.join(@libraries_root, 'src', 'a.mov') }
    let(:image_path) { File.join(@libraries_root, 'src', 'pic.png') }

    before do
      FileUtils.mkdir_p(File.dirname(video_path))
      FileUtils.touch(video_path)
      FileUtils.touch(image_path)
      allow(Library).to receive(:probe_duration).and_return('00:00:42')
    end

    it 'creates the directory tree, library.yaml, and returns a handle' do
      lib = Library.create(
        'fresh', language: 'en', editor: 'Final Cut Pro X',
        transcript_refinement: true, media_paths: [video_path]
      )
      expect(lib).to be_a(Library)
      expect(File.directory?(File.join(libraries_root, 'fresh', 'transcripts'))).to be(true)
      expect(File.directory?(File.join(libraries_root, 'fresh', 'cuts'))).to be(true)

      yaml = YAML.safe_load_file(File.join(libraries_root, 'fresh', 'library.yaml'), permitted_classes: [Date, Time])
      expect(yaml).to include(
        'library_name' => 'fresh', 'language' => 'en', 'editor' => 'Final Cut Pro X',
        'transcript_refinement' => true, 'user_context' => ''
      )
      expect(yaml['media'].first).to include(
        'path' => video_path, 'duration' => '00:00:42',
        'transcript' => '', 'contact_sheet' => '', 'summary' => ''
      )
    end

    it 'creates an image entry with only a summary field — no duration probe, no video fields' do
      Library.create(
        'fresh', language: 'en', editor: 'fcpx',
        transcript_refinement: false, media_paths: [image_path]
      )
      record = YAML.safe_load_file(File.join(libraries_root, 'fresh', 'library.yaml'), permitted_classes: [Date, Time])['media'].first
      expect(record).to include('path' => image_path, 'summary' => '')
      expect(record).not_to have_key('duration')
      expect(record).not_to have_key('transcript')
      expect(record).not_to have_key('contact_sheet')
    end

    it 'refuses to overwrite an existing library' do
      write_library(media: [], name: 'fresh')
      expect do
        Library.create('fresh', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, media_paths: [video_path])
      end.to raise_error(ArgumentError, /already exists/)
    end

    it 'raises when a media file is missing' do
      expect do
        Library.create('fresh', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, media_paths: ['/nope.mov'])
      end.to raise_error(ArgumentError, /media file not found/)
    end

    it 'rejects a media file whose extension no editor imports' do
      bad = File.join(@libraries_root, 'src', 'clip.mkv')
      FileUtils.touch(bad)
      expect do
        Library.create('fresh', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, media_paths: [bad])
      end.to raise_error(ArgumentError, /unsupported media format/)
    end

    it 'rejects a blank library name' do
      expect do
        Library.create('', language: 'en', editor: 'fcpx',
                       transcript_refinement: true, media_paths: [])
      end.to raise_error(ArgumentError, /library_name is required/)
    end
  end

  describe '#add_media' do
    let(:video_a) { File.join(@libraries_root, 'src', 'a.mov') }
    let(:video_b) { File.join(@libraries_root, 'src', 'b.mov') }
    let(:image_c) { File.join(@libraries_root, 'src', 'c.jpg') }

    before do
      FileUtils.mkdir_p(File.dirname(video_a))
      FileUtils.touch(video_a)
      FileUtils.touch(video_b)
      FileUtils.touch(image_c)
      allow(Library).to receive(:probe_duration).and_return('00:00:10')
      write_library(media: [video_entry('existing.mov', path: '/tmp/existing.mov')])
    end

    it 'appends new video entries with ffprobe duration and empty per-clip fields' do
      Library.find(library_name).add_media([video_a, video_b])
      media = load_yaml['media']
      expect(media.map { |v| v['path'] }).to eq(['/tmp/existing.mov', video_a, video_b])
      expect(media.last).to include('duration' => '00:00:10', 'transcript' => '', 'summary' => '')
    end

    it 'appends an image with only a summary field and no duration probe' do
      Library.find(library_name).add_media([image_c])
      record = load_yaml['media'].last
      expect(record['path']).to eq(image_c)
      expect(record).to include('summary' => '')
      expect(record).not_to have_key('duration')
      expect(record).not_to have_key('transcript')
    end

    it 'refuses to add a path already in the library' do
      Library.find(library_name).add_media([video_a])
      expect { Library.find(library_name).add_media([video_a]) }
        .to raise_error(ArgumentError, /media already in library/)
    end

    it 'raises if the media file does not exist on disk' do
      expect { Library.find(library_name).add_media(['/nope.mov']) }
        .to raise_error(ArgumentError, /media file not found/)
    end

    it 'rejects an extension outside every supported set' do
      bad = File.join(@libraries_root, 'src', 'clip.mkv')
      FileUtils.touch(bad)
      expect { Library.find(library_name).add_media([bad]) }
        .to raise_error(ArgumentError, /unsupported media format/)
    end

    it 'coerces a single path into a one-element array' do
      Library.find(library_name).add_media(video_a)
      expect(load_yaml['media'].last['path']).to eq(video_a)
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.add_media([video_a])).to be(lib)
    end

    it 'expands relative paths to absolute before storing' do
      stored = Dir.chdir(File.dirname(video_a)) do
        Library.find(library_name).add_media(['./a.mov'])
        load_yaml['media'].last['path']
      end
      expect(stored).to start_with('/')
      expect(stored).to end_with('/src/a.mov')
      expect(File.identical?(stored, video_a)).to be(true)
    end
  end

  describe '#remove_media!' do
    before do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg', summary: 'summary_a.md'),
                      image_entry('b.jpg', summary: 'summary_b_jpg.md')
                    ])
      touch(
        File.join(library_dir, 'transcripts', 'a.json'),
        File.join(library_dir, 'contact_sheets', 'a_full.jpg'),
        File.join(library_dir, 'summaries', 'summary_a.md'),
        File.join(library_dir, 'summaries', 'summary_b_jpg.md')
      )
    end

    it 'drops a video entry and deletes its artifacts' do
      Library.find(library_name).remove_media!(['a.mov'])
      expect(load_yaml['media'].map { |m| File.basename(m['path']) }).to eq(['b.jpg'])
      expect(File.exist?(File.join(library_dir, 'transcripts', 'a.json'))).to be(false)
      expect(File.exist?(File.join(library_dir, 'contact_sheets', 'a_full.jpg'))).to be(false)
      expect(File.exist?(File.join(library_dir, 'summaries', 'summary_a.md'))).to be(false)
    end

    it 'drops an image entry and deletes its summary' do
      Library.find(library_name).remove_media!(['b.jpg'])
      expect(load_yaml['media'].map { |m| File.basename(m['path']) }).to eq(['a.mov'])
      expect(File.exist?(File.join(library_dir, 'summaries', 'summary_b_jpg.md'))).to be(false)
    end

    it 'never deletes the source footage' do
      src = File.join(libraries_root, 'real-source.mov')
      FileUtils.touch(src)
      write_library(media: [video_entry('real-source.mov', path: src)])
      Library.find(library_name).remove_media!(['real-source.mov'])
      expect(File.exist?(src)).to be(true)
      expect(load_yaml['media']).to eq([])
    end

    it 'raises when the entry is not present in library.yaml' do
      expect { Library.find(library_name).remove_media!(['nope.mov']) }
        .to raise_error(ArgumentError, /media not found in library\.yaml/)
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.remove_media!(['b.jpg'])).to be(lib)
    end
  end

  describe '#unsupported_media' do
    it 'surfaces entries whose extension no editor imports natively' do
      write_library(media: [
                      video_entry('good.mov'),
                      video_entry('legacy.mkv', path: '/tmp/legacy.mkv')
                    ])
      result = Library.find(library_name).unsupported_media
      expect(result.map { |m| m['filename'] }).to eq(['legacy.mkv'])
      expect(result.first).to include('path' => '/tmp/legacy.mkv', 'extension' => 'mkv')
    end

    it 'returns an empty array when every entry is a supported type' do
      write_library(media: [video_entry('a.mov'), image_entry('b.jpg')])
      expect(Library.find(library_name).unsupported_media).to eq([])
    end
  end

  describe '.find' do
    it 'returns a Library instance for an existing library' do
      write_library(media: [])
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

  describe 'legacy videos: schema' do
    it 'refuses to load a library still on the videos: key, pointing at migrate' do
      FileUtils.mkdir_p(library_dir)
      File.write(library_yaml_path, { 'videos' => [] }.to_yaml)
      expect { Library.find(library_name).media }
        .to raise_error(/legacy `videos:` key.*migrate/m)
    end
  end

  describe '#summary' do
    it 'returns top-level metadata plus a clip-completion breakdown' do
      write_library(
        media: [
          video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg',
                      summary: 'summary_a.md'),
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
        'media_count' => 3,
        'complete_count' => 1,
        'incomplete_count' => 2
      )
      expect(result['incomplete'].map { |v| v['filename'] }).to eq(%w[b.mov c.mov])
      expect(result['incomplete'].first['missing']).to eq(%w[contact_sheet])
    end

    it 'breaks media_count down by registry type' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg', summary: 'summary_a.md'),
                      image_entry('b.jpg', summary: 'summary_b_jpg.md'),
                      image_entry('c.png')
                    ])
      result = Library.find(library_name).summary
      expect(result).to include('media_count' => 3, 'video_count' => 1, 'image_count' => 2)
    end

    it 'returns zero counts and an empty incomplete list for a brand-new empty library' do
      write_library(media: [], footage_summary: 'No footage analyzed yet.')
      result = Library.find(library_name).summary
      expect(result).to include('media_count' => 0, 'complete_count' => 0, 'incomplete_count' => 0, 'incomplete' => [])
      expect(result).to include('video_count' => 0, 'image_count' => 0)
    end

    it 'defaults free-text fields to empty strings when absent' do
      write_library(media: [])
      result = Library.find(library_name).summary
      expect(result['user_context']).to eq('')
      expect(result['footage_summary']).to eq('')
    end
  end

  describe '#dir' do
    it 'returns the absolute path to the library directory' do
      write_library(media: [])
      expect(Library.find(library_name).dir).to eq(library_dir)
    end
  end

  describe '#field_path' do
    before { write_library(media: []) }

    it 'returns the canonical on-disk path for each field' do
      lib = Library.find(library_name)
      expect(lib.field_path('transcript', 'DJI_0123')).to eq(File.join(library_dir, 'transcripts', 'DJI_0123.json'))
      expect(lib.field_path('contact_sheet', 'DJI_0123')).to eq(File.join(library_dir, 'contact_sheets', 'DJI_0123_full.jpg'))
      expect(lib.field_path('summary', 'DJI_0123')).to eq(File.join(library_dir, 'summaries', 'summary_DJI_0123.md'))
    end

    it 'strips the clip extension so a video basename with or without it resolves identically' do
      lib = Library.find(library_name)
      expect(lib.field_path('summary', 'P1055017.mov'))
        .to eq(lib.field_path('summary', 'P1055017'))
        .and eq(File.join(library_dir, 'summaries', 'summary_P1055017.md'))
    end

    it 'flattens the extension into image artifact names so photo and video basenames cannot collide' do
      lib = Library.find(library_name)
      expect(lib.field_path('summary', 'DJI_0123.jpg')).to eq(File.join(library_dir, 'summaries', 'summary_DJI_0123_jpg.md'))
      expect(lib.field_path('summary', 'DJI_0123.mov')).to eq(File.join(library_dir, 'summaries', 'summary_DJI_0123.md'))
    end

    it 'raises for unknown fields' do
      expect { Library.find(library_name).field_path('bogus', 'x') }
        .to raise_error(ArgumentError, /unknown field/)
    end
  end

  describe '#media' do
    it 'returns the media entries from library.yaml' do
      write_library(media: [video_entry('a.mov'), video_entry('b.mov')])
      media = Library.find(library_name).media
      expect(media.map { |v| v['path'] }).to eq(['/tmp/a.mov', '/tmp/b.mov'])
    end

    it 'exposes derived filename and type without persisting them to library.yaml' do
      write_library(media: [video_entry('a.mov'), image_entry('b.jpg')])
      library = Library.find(library_name)

      expect(library.media.map { |m| m['filename'] }).to eq(%w[a.mov b.jpg])
      expect(library.media.map { |m| m['type'] }).to eq(%w[video image])

      persisted = YAML.safe_load_file(library_yaml_path)['media']
      expect(persisted).to all(satisfy { |m| !m.key?('filename') && !m.key?('type') })
    end

    it 'reads an entry with an unrecognized extension as video (lenient read)' do
      write_library(media: [video_entry('legacy.mkv', path: '/tmp/legacy.mkv')])
      expect(Library.find(library_name).media.first['type']).to eq('video')
    end

    it 'returns an empty array when there is no media' do
      write_library(media: [])
      expect(Library.find(library_name).media).to eq([])
    end
  end

  describe 'metadata readers' do
    it 'returns top-level fields from library.yaml' do
      write_library(
        media: [],
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
      write_library(media: [])
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
      write_library(media: [], footage_summary: 'old summary', user_context: 'old context')
      Library.find(library_name).update_metadata!(footage_summary: 'new summary')
      reloaded = load_yaml
      expect(reloaded['footage_summary']).to eq('new summary')
      expect(reloaded['user_context']).to eq('old context')
    end

    it 'leaves untouched fields alone' do
      write_library(media: [], footage_summary: 'keep me', user_context: 'and me')
      Library.find(library_name).update_metadata!
      reloaded = load_yaml
      expect(reloaded['footage_summary']).to eq('keep me')
      expect(reloaded['user_context']).to eq('and me')
    end

    it 'accepts empty strings to clear a field' do
      write_library(media: [], footage_summary: 'old')
      Library.find(library_name).update_metadata!(footage_summary: '')
      expect(load_yaml['footage_summary']).to eq('')
    end

    it 'returns self for chaining' do
      write_library(media: [])
      lib = Library.find(library_name)
      expect(lib.update_metadata!(footage_summary: 'x')).to be(lib)
    end

    it 'updates the config fields (language, editor, transcript_refinement)' do
      write_library(media: [], language: '', editor: '', transcript_refinement: nil)
      Library.find(library_name).update_metadata!(language: 'english', editor: 'fcpx', transcript_refinement: false)
      reloaded = load_yaml
      expect(reloaded['language']).to eq('english')
      expect(reloaded['editor']).to eq('fcpx')
      expect(reloaded['transcript_refinement']).to be(false)
    end

    it 'writes transcript_refinement: false without treating it as "omitted"' do
      write_library(media: [], transcript_refinement: true)
      Library.find(library_name).update_metadata!(transcript_refinement: false)
      expect(load_yaml['transcript_refinement']).to be(false)
    end
  end

  describe '#incomplete_media' do
    it 'returns an empty array when every video has all three fields set' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', contact_sheet: 'a_full.jpg',
                                  summary: 'summary_a.md')
                    ])
      expect(Library.find(library_name).incomplete_media).to eq([])
    end

    it 'reports each missing field for a video' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json'),
                      video_entry('b.mov', transcript: 'b.json', summary: 'summary_b.md')
                    ])
      result = Library.find(library_name).incomplete_media
      expect(result.size).to eq(2)
      expect(result[0]).to include('filename' => 'a.mov', 'missing' => %w[contact_sheet summary])
      expect(result[1]).to include('filename' => 'b.mov', 'missing' => %w[contact_sheet])
    end

    it 'treats nil and whitespace-only values as missing' do
      write_library(media: [video_entry('a.mov', transcript: nil, contact_sheet: '   ')])
      expect(Library.find(library_name).incomplete_media.first['missing'])
        .to include('transcript', 'contact_sheet')
    end

    it 'reports only the summary field for an image (and omits it when present)' do
      write_library(media: [
                      image_entry('a.jpg'),
                      image_entry('b.png', summary: 'summary_b_png.md')
                    ])
      result = Library.find(library_name).incomplete_media
      expect(result.map { |m| m['filename'] }).to eq(['a.jpg'])
      expect(result.first['missing']).to eq(%w[summary])
    end

    it 'ignores legacy visual_transcript when reporting missing fields' do
      write_library(media: [
                      video_entry('a.mov', summary: 'summary_a.md').merge('visual_transcript' => 'visual_a.json')
                    ])
      expect(Library.find(library_name).incomplete_media.first['missing'])
        .to eq(%w[transcript contact_sheet])
    end
  end

  describe '#pending' do
    it 'returns records only for clips missing the named field' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json'),
                      video_entry('b.mov', transcript: ''),
                      video_entry('c.mov', transcript: 'c.json')
                    ])
      result = Library.find(library_name).pending('transcript')
      expect(result.map { |r| r['filename'] }).to eq(['b.mov'])
      expect(result.first).to include('path' => '/tmp/b.mov', 'duration' => '00:00:05')
    end

    it 'is independent per field' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', contact_sheet: ''),
                      video_entry('b.mov', transcript: '', contact_sheet: 'b_full.jpg')
                    ])
      library = Library.find(library_name)
      expect(library.pending('transcript').map { |r| r['filename'] }).to eq(['b.mov'])
      expect(library.pending('contact_sheet').map { |r| r['filename'] }).to eq(['a.mov'])
    end

    it 'never returns images for a video-only field (the WhisperX/ffmpeg pipeline never sees images)' do
      write_library(media: [
                      video_entry('a.mov', transcript: ''),
                      image_entry('b.jpg')
                    ])
      result = Library.find(library_name).pending('transcript')
      expect(result.map { |r| r['filename'] }).to eq(['a.mov'])
    end

    it 'returns images for summary, which applies to both types — and omits no-duration key for images' do
      write_library(media: [
                      video_entry('a.mov', summary: 'summary_a.md'),
                      image_entry('b.jpg')
                    ])
      result = Library.find(library_name).pending('summary')
      expect(result.map { |r| r['filename'] }).to eq(['b.jpg'])
      expect(result.first).to include('type' => 'image')
      expect(result.first).not_to have_key('duration')
    end

    it 'raises on an unknown field' do
      write_library(media: [])
      expect { Library.find(library_name).pending('nonsense') }.to raise_error(ArgumentError, /unknown field/)
    end
  end

  describe '#ready?' do
    it 'returns true when every video has transcript + summary (current pipeline)' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md'),
                      video_entry('b.mov', transcript: 'b.json', summary: 'summary_b.md')
                    ])
      expect(Library.find(library_name).ready?).to be(true)
    end

    it 'returns true when every video has visual_transcript + summary (legacy)' do
      write_library(media: [
                      video_entry('a.mov', summary: 'summary_a.md').merge('visual_transcript' => 'visual_a.json')
                    ])
      expect(Library.find(library_name).ready?).to be(true)
    end

    it 'accepts a mix of legacy and current videos' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md'),
                      video_entry('b.mov', summary: 'summary_b.md').merge('visual_transcript' => 'visual_b.json')
                    ])
      expect(Library.find(library_name).ready?).to be(true)
    end

    it 'returns true for an image once it has a summary (its only required field)' do
      write_library(media: [image_entry('a.jpg', summary: 'summary_a_jpg.md')])
      expect(Library.find(library_name).ready?).to be(true)
    end

    it 'is ready when a mix of video and image are each complete' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md'),
                      image_entry('b.jpg', summary: 'summary_b_jpg.md')
                    ])
      expect(Library.find(library_name).ready?).to be(true)
    end

    it 'returns false when any video is missing a summary' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md'),
                      video_entry('b.mov', transcript: 'b.json')
                    ])
      expect(Library.find(library_name).ready?).to be(false)
    end

    it 'returns false when an image is missing its summary' do
      write_library(media: [image_entry('a.jpg')])
      expect(Library.find(library_name).ready?).to be(false)
    end

    it 'returns false for an empty library' do
      write_library(media: [])
      expect(Library.find(library_name).ready?).to be(false)
    end

    it 'raises a migration-required error when a legacy roughcuts/ directory is present' do
      write_library(media: [video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md')])
      FileUtils.mkdir_p(File.join(library_dir, 'roughcuts'))

      expect { Library.find(library_name).ready? }
        .to raise_error(/legacy `roughcuts\/` directory.*library\.rb migrate/m)
    end
  end

  describe '#complete!' do
    before do
      write_library(media: [video_entry('a.mov'), video_entry('b.mov'), video_entry('c.mov')])
      touch(
        File.join(library_dir, 'summaries', 'summary_a.md'),
        File.join(library_dir, 'summaries', 'summary_b.md'),
        File.join(library_dir, 'summaries', 'summary_c.md')
      )
    end

    it 'sets the field on each named video' do
      Library.find(library_name).complete!('summary', ['a.mov', 'b.mov'])
      media = load_yaml['media']
      expect(media[0]['summary']).to eq('summary_a.md')
      expect(media[1]['summary']).to eq('summary_b.md')
      expect(media[2]['summary']).to eq('')
    end

    it 'sets summary on an image clip using the extension-flattened clip key' do
      write_library(media: [image_entry('photo.jpg')])
      touch(File.join(library_dir, 'summaries', 'summary_photo_jpg.md'))
      Library.find(library_name).complete!('summary', ['photo.jpg'])
      expect(load_yaml['media'][0]['summary']).to eq('summary_photo_jpg.md')
    end

    it 'raises when the field does not apply to the media type' do
      write_library(media: [image_entry('photo.jpg')])
      expect { Library.find(library_name).complete!('transcript', ['photo.jpg']) }
        .to raise_error(ArgumentError, /transcript does not apply to image media/)
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.complete!('summary', ['a.mov'])).to be(lib)
    end

    it 'raises if the file does not exist on disk and leaves YAML untouched' do
      File.delete(File.join(library_dir, 'summaries', 'summary_b.md'))
      expect { Library.find(library_name).complete!('summary', ['a.mov', 'b.mov']) }
        .to raise_error(ArgumentError, /summary file does not exist/)
      expect(load_yaml['media'][0]['summary']).to eq('')
    end

    it 'raises if a clip is not present in library.yaml' do
      touch(File.join(library_dir, 'summaries', 'summary_missing.md'))
      expect { Library.find(library_name).complete!('summary', ['missing.mov']) }
        .to raise_error(ArgumentError, /media not found in library\.yaml/)
    end

    it 'raises for an unknown field name' do
      expect { Library.find(library_name).complete!('bogus', ['a.mov']) }
        .to raise_error(ArgumentError, /unknown field/)
    end

    it 'coerces a single filename into a one-element batch' do
      Library.find(library_name).complete!('summary', 'a.mov')
      expect(load_yaml['media'][0]['summary']).to eq('summary_a.md')
    end
  end

  describe '#reset!' do
    before do
      write_library(media: [
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
      expect(load_yaml['media'].map { |v| v['summary'] }).to eq(['', ''])
    end

    it 'sweeps orphan files in the directory' do
      touch(File.join(library_dir, 'summaries', 'summary_orphan.md'))
      Library.find(library_name).reset!('summary')
      expect(Dir.children(File.join(library_dir, 'summaries'))).to eq([])
    end

    it 'is variadic — wipes every named field in one call' do
      write_library(media: [
                      video_entry('a.mov', transcript: 'a.json', summary: 'summary_a.md',
                                  contact_sheet: 'a_full.jpg')
                    ])
      touch(
        File.join(library_dir, 'transcripts',    'a.json'),
        File.join(library_dir, 'summaries',      'summary_a.md'),
        File.join(library_dir, 'contact_sheets', 'a_full.jpg')
      )
      Library.find(library_name).reset!('transcript', 'summary', 'contact_sheet')
      video = load_yaml['media'].first
      expect(video.values_at('transcript', 'summary', 'contact_sheet')).to eq(['', '', ''])
      expect(Dir.children(File.join(library_dir, 'transcripts'))).to eq([])
      expect(Dir.children(File.join(library_dir, 'summaries'))).to eq([])
      expect(Dir.children(File.join(library_dir, 'contact_sheets'))).to eq([])
    end

    it 'leaves legacy visual_*.json files alone when resetting transcripts' do
      write_library(media: [video_entry('a.mov', transcript: 'a.json').merge('visual_transcript' => 'visual_a.json')])
      touch(
        File.join(library_dir, 'transcripts', 'a.json'),
        File.join(library_dir, 'transcripts', 'visual_a.json')
      )
      Library.find(library_name).reset!('transcript')
      expect(Dir.children(File.join(library_dir, 'transcripts'))).to eq(['visual_a.json'])
      expect(load_yaml['media'].first['visual_transcript']).to eq('visual_a.json')
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
      yaml = load_yaml['media']
      expect(yaml[0]['summary']).to eq('summary_a.md') # not cleared — delete failed
      expect(yaml[1]['summary']).to eq('')             # cleared — delete succeeded
    end
  end

  describe '#reset_metadata!' do
    before do
      write_library(
        media: [video_entry('a.mov')],
        created_date: '2026-05-30', last_updated: '2026-05-30',
        language: 'english', editor: 'fcpx', transcript_refinement: true,
        footage_summary: 'A vlog about Ruby meetups.', user_context: 'Subject is named Andrew.'
      )
    end

    it 'clears setup choices and analysis-derived context to an unconfigured state' do
      Library.find(library_name).reset_metadata!
      yaml = load_yaml
      expect(yaml.values_at('language', 'editor', 'footage_summary', 'user_context')).to eq(['', '', '', ''])
      expect(yaml['transcript_refinement']).to be_nil
      expect(yaml.key?('transcript_refinement')).to be(true) # key kept so 002 migration treats it as set
    end

    it 'keeps media records and dates' do
      Library.find(library_name).reset_metadata!
      yaml = load_yaml
      expect(yaml['media'].map { |v| v['path'] }).to eq(['/tmp/a.mov'])
      expect(yaml.values_at('created_date', 'last_updated')).to eq(['2026-05-30', '2026-05-30'])
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.reset_metadata!).to be(lib)
    end
  end

  describe '#remove_visual_transcripts!' do
    before do
      write_library(media: [
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
      expect(load_yaml['media'].map { |v| v['visual_transcript'] }).to eq(['', ''])
    end

    it 'leaves non-visual transcript files and other YAML fields intact' do
      Library.find(library_name).remove_visual_transcripts!
      yaml = load_yaml['media']
      expect(yaml.map { |v| v['transcript'] }).to eq(%w[a.json b.json])
    end

    it 'is a no-op when no visual transcripts are present' do
      FileUtils.rm_rf(File.join(library_dir, 'transcripts'))
      FileUtils.mkdir_p(File.join(library_dir, 'transcripts'))
      write_library(media: [video_entry('a.mov', transcript: 'a.json')])
      touch(File.join(library_dir, 'transcripts', 'a.json'))
      expect { Library.find(library_name).remove_visual_transcripts! }.not_to raise_error
      expect(Dir.children(File.join(library_dir, 'transcripts'))).to eq(['a.json'])
    end

    it 'returns self for chaining' do
      lib = Library.find(library_name)
      expect(lib.remove_visual_transcripts!).to be(lib)
    end
  end

  describe 'concurrent writers (#mutate flock transaction)' do
    # The real-world scenario this guards: `process_footage.rb` runs in the
    # background recording transcripts via complete!, while the agent updates
    # footage_summary "as transcripts come in" — two separate OS processes each
    # doing a full read-modify-write of library.yaml. Without a lock spanning the
    # whole RMW, the later rename silently drops the other process's change.
    it 'loses no updates when two processes write library.yaml at once' do
      skip 'fork unavailable on this platform' unless Process.respond_to?(:fork)

      n = 30
      clips = Array.new(n) { |i| "clip#{i}.mov" }
      write_library(media: clips.map { |c| video_entry(c) }, footage_summary: '')
      clips.each { |c| touch(File.join(library_dir, 'transcripts', "#{File.basename(c, '.*')}.json")) }

      # Child: record each clip's transcript as its own complete! call.
      child = fork do
        clips.each do |c|
          Library.find(library_name).complete!('transcript', [c], announce: false)
          sleep(0.001)
        end
        exit!(0)
      end

      # Parent: hammer footage_summary in parallel. Its last write must survive —
      # complete! reads-and-preserves footage_summary under the same lock, so a
      # concurrent transcript write can never revert it.
      n.times do |i|
        Library.find(library_name).update_metadata!(footage_summary: "summary-#{i}")
        sleep(0.001)
      end
      Library.find(library_name).update_metadata!(footage_summary: 'FINAL')

      _, status = Process.wait2(child)
      expect(status.success?).to be(true)

      yaml = load_yaml
      # Every transcript landed (child's writes weren't clobbered by the parent)...
      expect(yaml['media'].map { |v| v['transcript'] }).to all(satisfy { |t| !t.to_s.empty? })
      # ...and the parent's final metadata write survived (not reverted by a
      # concurrent complete!).
      expect(yaml['footage_summary']).to eq('FINAL')
    end
  end

  describe '.check_for_update! / .record_update_check!' do
    around do |example|
      Dir.mktmpdir('update-check-') do |root|
        @repo_root = root
        example.run
      end
    end

    let(:stamp) { File.join(@repo_root, Library::UPDATE_CHECK_FILE) }

    def age_stamp(seconds_ago)
      FileUtils.touch(stamp)
      t = Time.now - seconds_ago
      File.utime(t, t, stamp)
    end

    it 'seeds the stamp and stays quiet on a fresh checkout (no stamp yet)' do
      expect(File.exist?(stamp)).to be(false)
      expect { Library.check_for_update!(repo_root: @repo_root) }.not_to raise_error
      expect(File.exist?(stamp)).to be(true)
    end

    it 'raises when the last check was more than a day ago' do
      age_stamp(Library::UPDATE_CHECK_INTERVAL + 60)
      expect { Library.check_for_update!(repo_root: @repo_root) }.to raise_error(Library::UpdateCheckNeeded)
    end

    it 'does not raise when a check was recorded within the last day' do
      age_stamp(60)
      expect { Library.check_for_update!(repo_root: @repo_root) }.not_to raise_error
    end

    it 'record_update_check! writes the stamp so the next check stays quiet' do
      expect(File.exist?(stamp)).to be(false)
      Library.record_update_check!(repo_root: @repo_root)
      expect(File.exist?(stamp)).to be(true)
      expect { Library.check_for_update!(repo_root: @repo_root) }.not_to raise_error
    end
  end

  describe 'CLI edition command' do
    # Asserted against the constant (not a literal) so this spec file stays
    # byte-identical across the core and pro editions.
    it 'prints ButterCut::EDITION and exits 0' do
      cli = File.expand_path('../../lib/buttercut/library.rb', __dir__)
      out = `ruby #{Shellwords.escape(cli)} edition`
      expect($CHILD_STATUS.exitstatus).to eq(0)
      expect(out.strip).to eq(ButterCut::EDITION.to_s)
    end
  end
end
