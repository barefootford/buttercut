require 'spec_helper'
require_relative '../../lib/buttercut/media'

RSpec.describe Media do
  describe 'classification (.image? / .video? / .needs_conversion? / .supported?)' do
    image_paths = %w[
      photo.jpg a.jpeg b.png c.gif d.tif e.tiff f.webp i.bmp
      /abs/path/to/sunset.png nested/dir/IMG_1234.JPG
    ]
    video_paths = %w[
      clip.mov a.mp4 b.MOV c.avi d.mkv e.m4v f.mts g.m2ts h.mxf i.r3d j.braw /abs/k.mov L.MP4
    ]
    convert_paths = %w[photo.heic a.HEIC b.heif /abs/IMG_9999.HEIC]
    unsupported_paths = %w[notes.txt archive.zip .DS_Store report.pdf noextension a.srt]

    image_paths.each do |path|
      it "treats #{path} as a directly-usable image" do
        expect(Media.image?(path)).to be(true)
        expect(Media.video?(path)).to be(false)
        expect(Media.needs_conversion?(path)).to be(false)
        expect(Media.supported?(path)).to be(true)
      end
    end

    video_paths.each do |path|
      it "treats #{path} as video" do
        expect(Media.video?(path)).to be(true)
        expect(Media.image?(path)).to be(false)
        expect(Media.needs_conversion?(path)).to be(false)
        expect(Media.supported?(path)).to be(true)
      end
    end

    convert_paths.each do |path|
      it "treats #{path} as a still that needs conversion (not a directly-usable image)" do
        expect(Media.needs_conversion?(path)).to be(true)
        expect(Media.image?(path)).to be(false)
        expect(Media.video?(path)).to be(false)
        expect(Media.supported?(path)).to be(true)
      end
    end

    unsupported_paths.each do |path|
      it "treats #{path} as unsupported" do
        expect(Media.supported?(path)).to be(false)
        expect(Media.image?(path)).to be(false)
        expect(Media.video?(path)).to be(false)
        expect(Media.needs_conversion?(path)).to be(false)
      end
    end

    it 'matches the extension case-insensitively' do
      expect(Media.image?('IMG_1234.JPG')).to be(true)
      expect(Media.needs_conversion?('IMG_1234.HeIc')).to be(true)
      expect(Media.video?('CLIP.MOV')).to be(true)
    end

    it 'treats nil and empty paths as unsupported (no extension)' do
      [nil, ''].each do |blank|
        expect(Media.image?(blank)).to be(false)
        expect(Media.video?(blank)).to be(false)
        expect(Media.needs_conversion?(blank)).to be(false)
        expect(Media.supported?(blank)).to be(false)
      end
    end

    it 'accepts a Pathname-like object via to_s' do
      expect(Media.image?(Pathname.new('/footage/a.png'))).to be(true)
      expect(Media.video?(Pathname.new('/footage/a.mov'))).to be(true)
      expect(Media.needs_conversion?(Pathname.new('/footage/a.heic'))).to be(true)
    end
  end

  describe '.convert_to_jpeg' do
    it 'raises when the source image does not exist' do
      expect { Media.convert_to_jpeg('/nope/missing.heic', '/tmp/out.jpg') }
        .to raise_error(ArgumentError, /source image not found/)
    end
  end
end
